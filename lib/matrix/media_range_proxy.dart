import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:vodozemac/vodozemac.dart';

typedef RangeDecryptor = Uint8List Function(
  Uint8List input,
  Uint8List key,
  Uint8List iv,
  int blockOffset,
);

/// Serves encrypted Matrix media to a local player using bounded HTTP ranges.
///
/// Matrix attachments use AES-CTR, so an aligned ciphertext range can be
/// decrypted independently by advancing the counter by its block offset. This
/// keeps seeking and playback streaming without exposing credentials or keys
/// in a URL visible outside the loopback interface.
class MediaRangeProxy {
  MediaRangeProxy({RangeDecryptor? decryptor})
    : _decryptor = decryptor ?? _decryptAesCtrRange;

  final RangeDecryptor _decryptor;
  HttpServer? _server;
  final HttpClient _upstream = HttpClient();
  final Map<String, _EncryptedMedia> _entries = {};
  final Random _random = Random.secure();

  Future<Uri> register({
    required Uri upstream,
    required String accessToken,
    required Uint8List key,
    required Uint8List iv,
    required int size,
    required String mimeType,
  }) async {
    final server = await _ensureServer();
    final token = List.generate(24, (_) => _random.nextInt(256));
    final id = base64UrlEncode(token).replaceAll('=', '');
    _entries[id] = _EncryptedMedia(
      upstream: upstream,
      accessToken: accessToken,
      key: key,
      iv: iv,
      size: size,
      mimeType: mimeType,
    );
    return Uri.parse('http://127.0.0.1:${server.port}/media/$id');
  }

  Future<HttpServer> _ensureServer() async {
    final existing = _server;
    if (existing != null) return existing;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    unawaited(server.forEach(_handle));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    final id =
        request.uri.pathSegments.length == 2 &&
            request.uri.pathSegments.first == 'media'
        ? request.uri.pathSegments.last
        : null;
    final media = id == null ? null : _entries[id];
    if (media == null ||
        (request.method != 'GET' && request.method != 'HEAD')) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    try {
      final requested = _parseRange(request.headers.value('range'), media.size);
      final start = requested.$1;
      final end = requested.$2;
      final length = end - start + 1;
      final response = request.response
        ..bufferOutput = false
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.set(HttpHeaders.contentTypeHeader, media.mimeType)
        ..headers.set(HttpHeaders.contentLengthHeader, length)
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${media.size}',
        );
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }

      final alignedStart = start - (start % 16);
      await _streamDecryptedRange(
        media,
        fetchStart: alignedStart,
        requestedStart: start,
        requestedEnd: end,
        downstream: response,
      );
      await response.close();
    } catch (_) {
      // A streaming response may already have sent its headers. In that case
      // changing the status is no longer legal, but closing it still lets the
      // player retry the failed range safely.
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
      try {
        await request.response.close();
      } catch (_) {}
    }
  }

  (int, int) _parseRange(String? header, int size) {
    // Larger sequential ranges substantially reduce proxy/upstream round trips
    // for high-bitrate video while remaining bounded for encrypted playback.
    const maxChunk = 16 * 1024 * 1024;
    if (size <= 0) throw const FormatException('Empty media');
    if (header == null || !header.startsWith('bytes=')) {
      return (0, min(size, maxChunk) - 1);
    }
    final parts = header.substring(6).split('-');
    if (parts.length != 2) {
      throw const FormatException('Invalid media range');
    }
    final suffixLength = parts.first.isEmpty ? int.tryParse(parts[1]) : null;
    final int? start = suffixLength == null
        ? int.tryParse(parts.first)
        : max(0, size - min(size, suffixLength));
    if (start == null || suffixLength == 0) {
      throw const FormatException('Invalid media range');
    }
    final requestedEnd = suffixLength == null ? int.tryParse(parts[1]) : null;
    final end = min(
      size - 1,
      min(requestedEnd ?? size - 1, start + maxChunk - 1),
    );
    if (start < 0 || start >= size || end < start) {
      throw const FormatException('Invalid media range');
    }
    return (start, end);
  }

  /// Streams an independently decryptable AES-CTR range to the player.
  ///
  /// Only an incomplete cipher block is buffered between upstream chunks.
  /// Previously the full (up to 16 MiB) range was downloaded and decrypted
  /// before playback received any data, producing long startup stalls.
  Future<void> _streamDecryptedRange(
    _EncryptedMedia media, {
    required int fetchStart,
    required int requestedStart,
    required int requestedEnd,
    required HttpResponse downstream,
  }) async {
    final request = await _upstream.getUrl(media.upstream);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${media.accessToken}')
      ..set(HttpHeaders.rangeHeader, 'bytes=$fetchStart-$requestedEnd');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Media server returned ${response.statusCode}');
    }

    final cipherLength = requestedEnd - fetchStart + 1;
    final requestedLength = requestedEnd - requestedStart + 1;
    var upstreamSkip = response.statusCode == HttpStatus.ok ? fetchStart : 0;
    var cipherRemaining = cipherLength;
    var cipherOffset = fetchStart;
    var emitted = 0;
    var pending = Uint8List(0);

    await for (final rawChunk in response) {
      var rawOffset = 0;
      if (upstreamSkip > 0) {
        final skipped = min(upstreamSkip, rawChunk.length);
        upstreamSkip -= skipped;
        rawOffset += skipped;
      }
      if (rawOffset >= rawChunk.length || cipherRemaining == 0) continue;

      final take = min(cipherRemaining, rawChunk.length - rawOffset);
      final combined = Uint8List(pending.length + take)
        ..setRange(0, pending.length, pending)
        ..setRange(pending.length, pending.length + take, rawChunk, rawOffset);
      cipherRemaining -= take;

      // Keep a partial AES block until the next upstream chunk. At the end of
      // the requested range AES-CTR can safely decrypt the final partial block.
      final processLength = cipherRemaining == 0
          ? combined.length
          : combined.length - (combined.length % 16);
      if (processLength == 0) {
        pending = combined;
        continue;
      }

      final encrypted = Uint8List.sublistView(combined, 0, processLength);
      final decrypted = _decryptor(
        encrypted,
        media.key,
        media.iv,
        cipherOffset ~/ 16,
      );
      final segmentStart = cipherOffset;
      final segmentEnd = cipherOffset + processLength;
      final outputStart = max(requestedStart, segmentStart) - segmentStart;
      final outputEnd = min(requestedEnd + 1, segmentEnd) - segmentStart;
      if (outputEnd > outputStart) {
        downstream.add(
          Uint8List.sublistView(decrypted, outputStart, outputEnd),
        );
        emitted += outputEnd - outputStart;
        // bufferOutput is disabled, so media_kit sees this block immediately
        // without serializing every upstream chunk behind a flush round trip.
      }
      cipherOffset += processLength;
      pending = processLength == combined.length
          ? Uint8List(0)
          : Uint8List.sublistView(combined, processLength);
      if (cipherRemaining == 0) break;
    }

    if (cipherRemaining != 0 ||
        pending.isNotEmpty ||
        emitted != requestedLength) {
      throw const HttpException('Incomplete encrypted media range');
    }
  }

  void clear() => _entries.clear();

  Future<void> close() async {
    _entries.clear();
    _upstream.close(force: true);
    await _server?.close(force: true);
    _server = null;
  }
}

Uint8List _decryptAesCtrRange(
  Uint8List input,
  Uint8List key,
  Uint8List iv,
  int blockOffset,
) =>
    CryptoUtils.aesCtr(input: input, key: key, iv: _counterAt(iv, blockOffset));

Uint8List _counterAt(Uint8List iv, int blockOffset) {
  final counter = Uint8List.fromList(iv);
  var carry = blockOffset;
  for (var index = counter.length - 1; index >= 8 && carry > 0; index--) {
    final value = counter[index] + (carry & 0xff);
    counter[index] = value & 0xff;
    carry = (carry >> 8) + (value >> 8);
  }
  if (carry != 0) throw StateError('Encrypted media counter overflow');
  return counter;
}

class _EncryptedMedia {
  const _EncryptedMedia({
    required this.upstream,
    required this.accessToken,
    required this.key,
    required this.iv,
    required this.size,
    required this.mimeType,
  });

  final Uri upstream;
  final String accessToken;
  final Uint8List key;
  final Uint8List iv;
  final int size;
  final String mimeType;
}
