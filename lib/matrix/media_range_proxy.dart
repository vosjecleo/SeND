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
      final prefix = start - alignedStart;
      final encrypted = await _fetchRange(media, alignedStart, end);
      final decrypted = _decryptor(
        encrypted,
        media.key,
        media.iv,
        alignedStart ~/ 16,
      );
      response.add(decrypted.sublist(prefix, prefix + length));
      await response.close();
    } catch (_) {
      request.response.statusCode = HttpStatus.badGateway;
      await request.response.close();
    }
  }

  (int, int) _parseRange(String? header, int size) {
    const maxChunk = 4 * 1024 * 1024;
    if (header == null || !header.startsWith('bytes=')) {
      return (0, min(size, maxChunk) - 1);
    }
    final parts = header.substring(6).split('-');
    final start = int.tryParse(parts.first) ?? 0;
    final requestedEnd = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final end = min(
      size - 1,
      min(requestedEnd ?? size - 1, start + maxChunk - 1),
    );
    if (start < 0 || start >= size || end < start) {
      throw const FormatException('Invalid media range');
    }
    return (start, end);
  }

  Future<Uint8List> _fetchRange(
    _EncryptedMedia media,
    int start,
    int end,
  ) async {
    final request = await _upstream.getUrl(media.upstream);
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${media.accessToken}')
      ..set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      throw HttpException('Media server returned ${response.statusCode}');
    }

    final needed = end - start + 1;
    var skip = response.statusCode == HttpStatus.ok ? start : 0;
    final bytes = BytesBuilder(copy: false);
    late StreamSubscription<List<int>> subscription;
    final done = Completer<void>();
    subscription = response.listen(
      (chunk) {
        var offset = 0;
        if (skip > 0) {
          final skipped = min(skip, chunk.length);
          skip -= skipped;
          offset += skipped;
        }
        if (offset < chunk.length && bytes.length < needed) {
          final take = min(needed - bytes.length, chunk.length - offset);
          bytes.add(chunk.sublist(offset, offset + take));
        }
        if (bytes.length >= needed && !done.isCompleted) {
          done.complete();
          unawaited(subscription.cancel());
        }
      },
      onError: done.completeError,
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    final result = bytes.takeBytes();
    if (result.length != needed) {
      throw const HttpException('Incomplete encrypted media range');
    }
    return result;
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
