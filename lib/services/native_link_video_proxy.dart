import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'platform_io.dart';
import 'link_preview_service.dart';
import 'socks_proxy.dart';
import 'native_video_player_options.dart';
import 'package:media_kit/media_kit.dart';

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
  int _active = 0;
  int _transferred = 0;
  bool _closed = false;
  bool _reserved = false;
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

  Future<void> _serve(HttpRequest request) async {
    if (_closed ||
        request.uri.path != '/media/$_token' ||
        request.uri.hasQuery ||
        !['GET', 'HEAD'].contains(request.method) ||
        _active >= 2) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    _active++;
    StreamSubscription<List<int>>? subscription;
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && !RegExp(r'^bytes=\d*-\d*$').hasMatch(range)) {
        throw const FormatException('Invalid media range');
      }
      final upstream = await _fetcher.openVideo(_upstream!, range: range);
      request.response.statusCode = upstream.statusCode;
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, upstream.contentType!)
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
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
        await done.future;
      }
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {
        /* Headers sent. */
      }
    } finally {
      await subscription?.cancel();
      _active--;
      try {
        await request.response.close();
      } catch (_) {
        /* Player closed. */
      }
    }
  }

  Future<void> close() async {
    _closed = true;
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
