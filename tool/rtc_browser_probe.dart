import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Loopback-only, nonce-protected handoff. Passwords stay out of arguments,
/// browser logs and compiled assets. The browser uses a disposable profile.
class RtcBrowserProbe {
  HttpServer? _server;
  Process? _process;
  bool _stop = false;
  bool requestCamera = false;
  final _finished = Completer<void>();
  Map<String, dynamic>? result;
  Future<void> start(String user, String password, String roomId) async {
    final nonce = List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((request) async {
      final response = request.response;
      response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
      response.headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
      response.headers.set('Cache-Control', 'no-store');
      if (request.uri.path.startsWith('/probe/')) {
        if (request.uri.queryParameters['nonce'] != nonce) {
          response.statusCode = 403;
        } else {
          response.headers.contentType = ContentType.json;
          switch (request.uri.path) {
            case '/probe/fixture':
              response.write(
                jsonEncode({
                  'user': user,
                  'password': password,
                  'room': roomId,
                }),
              );
            case '/probe/stop':
              response.write(
                jsonEncode({'stop': _stop, 'camera': requestCamera}),
              );
            case '/probe/result':
              final bytes = <int>[];
              await for (final chunk in request) {
                bytes.addAll(chunk);
                if (bytes.length > 2048) break;
              }
              if (bytes.length <= 2048) {
                result = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
              }
              response.write('{}');
            case '/probe/finished':
              if (!_finished.isCompleted) _finished.complete();
              response.write('{}');
            default:
              response.statusCode = 404;
          }
        }
      } else {
        final path = request.uri.path == '/' ? '/index.html' : request.uri.path;
        final segments = path.split('/');
        if (segments.any((s) => s == '..' || s.contains('\\'))) {
          response.statusCode = 403;
        } else {
          final file = File('.dart_tool/rtc-web-probe$path');
          if (!await file.exists()) {
            response.statusCode = 404;
          } else {
            response.headers.set('Content-Type', switch (path.split('.').last) {
              'js' => 'application/javascript',
              'wasm' => 'application/wasm',
              'html' => 'text/html',
              'json' => 'application/json',
              _ => 'application/octet-stream',
            });
            await response.addStream(file.openRead());
          }
        }
      }
      await response.close();
    });
    _process = await Process.start(
      'node',
      [
        'tool/rtc_live_browser.mjs',
        'http://127.0.0.1:${_server!.port}/?nonce=$nonce',
      ],
      environment: {
        'PUPPETEER_MODULE':
            '${Directory.current.path}/tool/browser-tests/node_modules/puppeteer-core/lib/puppeteer/puppeteer-core.js',
      },
    );
    // Never forward raw browser console or network errors.
    _process!.stdout.drain<void>();
    _process!.stderr.drain<void>();
  }

  Future<void> close() async {
    _stop = true;
    try {
      await _finished.future.timeout(const Duration(seconds: 30));
    } catch (_) {}
    _process?.kill();
    await _process?.exitCode.timeout(const Duration(seconds: 10));
    await _server?.close(force: true);
  }
}
