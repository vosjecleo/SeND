import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'platform_io.dart';
import 'link_preview_service.dart';
import 'socks_proxy.dart';
import 'native_video_player_options.dart';
import 'package:media_kit/media_kit.dart';

class _VideoTransfer {
  final cancelled = Completer<void>();
  final released = Completer<void>();
  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
  }
}

bool _validSeekRange(String value) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(value);
  if (match == null) return false;
  final start = int.tryParse(match[1]!);
  final end = int.tryParse(match[2]!);
  if (match[1]!.isEmpty) return end != null && end > 0;
  return start != null && (match[2]!.isEmpty || end != null && end >= start);
}

/// Capability URL for a single video. The player never receives an origin URL.
/// Every seek/reconnect goes through the pinned public-only preview transport.
class NativeLinkVideoProxy {
  NativeLinkVideoProxy({DirectLinkPreviewFetcher? fetcher})
    : _fetcher = fetcher ?? DirectLinkPreviewFetcher();
  final DirectLinkPreviewFetcher _fetcher;
  HttpServer? _server;
  Uri? _upstream;
  String? _token;
  String? format;
  final _transfers = <_VideoTransfer>[];
  Future<void> _admission = Future.value();
  int _waiting = 0;
  int _transferred = 0;
  bool _closed = false;
  bool _reserved = false;
  bool _supportsRanges = false;
  static int _instances = 0;

  Future<Uri> open(Uri upstream) async {
    if (_closed || _reserved || _instances >= 8) {
      throw StateError('Too many embedded videos are open.');
    }
    _reserved = true;
    _instances++;
    try {
      return await _open(upstream);
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<Uri> _open(Uri upstream) async {
    if (SocksProxy.blockDirectTraffic) {
      throw StateError('Direct previews are blocked by your proxy settings.');
    }
    // Sniff through the same validated connection path, not the native player.
    final probe = await _fetcher.openVideo(upstream, range: 'bytes=0-31');
    _supportsRanges = probe.statusCode == HttpStatus.partialContent;
    final prefix = BytesBuilder(copy: false);
    await for (final chunk in probe.body.timeout(const Duration(seconds: 10))) {
      prefix.add(chunk.take(32 - prefix.length).toList());
      if (prefix.length >= 32) break;
    }
    final bytes = prefix.takeBytes();
    format = containerFormat(bytes);
    if (format == null) throw StateError('Unsupported embedded video format.');
    if (_closed) throw StateError('Video was closed.');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_closed) {
      await server.close(force: true);
      throw StateError('Video was closed.');
    }
    _server = server;
    _upstream = upstream;
    _token = base64UrlEncode(
      List.generate(24, (_) => Random.secure().nextInt(256)),
    );
    server.listen((request) => unawaited(_serve(request)));
    return Uri.parse('http://127.0.0.1:${server.port}/media/$_token');
  }

  Future<Uri> openForPlayer(Player player, Uri upstream) async {
    final local = await open(upstream);
    // Do not let container references or a disguised playlist create a second
    // network path in mpv/libavformat, bypassing the validated local proxy.
    await restrictNativeVideoPlayer(player, format!);
    return local;
  }

  Future<void> openAndPlay(Player player, Uri upstream) async {
    final local = await openForPlayer(player, upstream);
    await openRestrictedNativeVideo(player, local);
  }

  static String? containerFormat(List<int> bytes) {
    if (bytes.length < 12) return null;
    String ascii(int start, int end) =>
        String.fromCharCodes(bytes.sublist(start, end));
    if (['ftyp', 'moov', 'mdat', 'free', 'wide'].contains(ascii(4, 8))) {
      return 'mov';
    }
    if (bytes[0] == 0x1a &&
        bytes[1] == 0x45 &&
        bytes[2] == 0xdf &&
        bytes[3] == 0xa3) {
      return 'matroska';
    }
    if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'AVI ') return 'avi';
    if (ascii(0, 4) == 'OggS') return 'ogg';
    if (ascii(0, 3) == 'FLV') return 'flv';
    return null; // Includes HLS/DASH/HTML and renamed playlists.
  }

  Future<_VideoTransfer?> _admit(String? range) async {
    // Bound both active origins and queued local requests. A seek may leave
    // old decoder read-ahead connections open, so retire the oldest transfer
    // instead of reporting a fatal HTTP error to the newest seek.
    if (_waiting >= 2 || _closed) return null;
    _waiting++;
    final previous = _admission;
    final gate = Completer<void>();
    _admission = gate.future;
    try {
      await previous;
      if (_closed) return null;
      if (_transfers.length >= 2) {
        if (range == null) return null;
        final oldest = _transfers.first;
        oldest.cancel();
        // Release only after its upstream subscription has been cancelled.
        // New requests never increase the number of live origin transfers.
        await oldest.released.future;
      }
      if (_closed) return null;
      final transfer = _VideoTransfer();
      _transfers.add(transfer);
      return transfer;
    } finally {
      _waiting--;
      gate.complete();
    }
  }

  Future<void> _serve(HttpRequest request) async {
    if (_closed ||
        request.uri.path != '/media/$_token' ||
        request.uri.hasQuery ||
        !['GET', 'HEAD'].contains(request.method)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && !_validSeekRange(range)) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    final transfer = await _admit(range);
    if (transfer == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.headers.set(HttpHeaders.retryAfterHeader, '1');
      await request.response.close();
      return;
    }
    StreamSubscription<List<int>>? subscription;
    try {
      final upstream = await _fetcher.openVideo(_upstream!, range: range);
      if (transfer.cancelled.isCompleted || _closed) {
        await upstream.body.listen((_) {}).cancel();
        return;
      }
      request.response.statusCode = upstream.statusCode;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, upstream.contentType!)
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      if (_supportsRanges || upstream.statusCode == HttpStatus.partialContent) {
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      }
      if (upstream.contentRange != null) {
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          upstream.contentRange!,
        );
      }
      if (upstream.contentLength >= 0) {
        request.response.contentLength = upstream.contentLength;
      }
      var bytes = 0;
      final stream = upstream.body.timeout(const Duration(seconds: 10));
      if (request.method == 'HEAD') {
        await stream.listen((_) {}).cancel();
      } else {
        final done = Completer<void>();
        subscription = stream.listen(null);
        subscription.onData((chunk) {
          bytes += chunk.length;
          _transferred += chunk.length;
          if (_closed ||
              transfer.cancelled.isCompleted ||
              bytes > 512 * 1024 * 1024 ||
              _transferred > 1024 * 1024 * 1024) {
            if (!done.isCompleted) {
              done.completeError(StateError('Video transfer limit exceeded.'));
            }
            return;
          }
          subscription!.pause();
          request.response.add(chunk);
          request.response.flush().then(
            (_) => subscription?.resume(),
            onError: (Object e, StackTrace s) {
              if (!done.isCompleted) done.completeError(e, s);
            },
          );
        });
        subscription.onDone(() {
          if (!done.isCompleted) done.complete();
        });
        subscription.onError((Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e, s);
        });
        unawaited(
          request.response.done.catchError((Object _) {}).then((_) {
            if (!done.isCompleted) done.complete();
          }),
        );
        await Future.any([done.future, transfer.cancelled.future]);
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        /* Headers sent. */
      }
    } finally {
      try {
        await subscription?.cancel();
      } finally {
        _transfers.remove(transfer);
        transfer.released.complete();
      }
      try {
        await request.response.close();
      } catch (_) {
        /* Player closed. */
      }
    }
  }

  Future<void> close() async {
    _closed = true;
    for (final transfer in _transfers) {
      transfer.cancel();
    }
    final server = _server;
    _server = null;
    if (_reserved) {
      _instances--;
      _reserved = false;
    }
    if (server != null) {
      await server.close(force: true);
    }
  }
}
