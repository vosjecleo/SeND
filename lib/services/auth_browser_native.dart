import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

/// External system browser with an ephemeral loopback callback. No embedded
/// webview, persistent callback token file or new desktop browser dependency.
class AuthBrowser {
  AuthBrowser._(this._server, this.redirect) {
    unawaited(
      _result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final HttpServer _server;
  final Uri redirect;
  final _result = Completer<Uri>();
  StreamSubscription<HttpRequest>? _subscription;
  bool _closed = false;

  static Future<AuthBrowser> prepare(String nonce) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final browser = AuthBrowser._(
      server,
      Uri.parse('http://127.0.0.1:${server.port}/auth/$nonce'),
    );
    browser._subscription = server.listen((request) async {
      if (request.method != 'GET' ||
          request.uri.path != browser.redirect.path) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final uri = browser.redirect.replace(query: request.uri.query);
      request.response.headers
        ..contentType = ContentType.html
        ..set('Cache-Control', 'no-store')
        ..set('Referrer-Policy', 'no-referrer')
        ..set(
          'Content-Security-Policy',
          "default-src 'none'; script-src 'nonce-$nonce'",
        );
      request.response.write(
        '<!doctype html><title>Deltiecord sign-in</title>'
        '<script nonce="$nonce">history.replaceState(null,"",location.pathname)</script>'
        '<p>Return to Deltiecord to finish signing in. You can close this tab.</p>'
        '${Platform.isAndroid ? '<a href="net.deltie.deltiecord://login-complete">Open Deltiecord</a>' : ''}',
      );
      await request.response.close();
      if (!browser._result.isCompleted) browser._result.complete(uri);
    });
    return browser;
  }

  Future<Uri> authenticate(Uri authorization) async {
    if (_closed) throw StateError('Sign-in canceled');
    if (!await launchUrl(authorization, mode: LaunchMode.externalApplication)) {
      throw StateError('Could not open the system browser.');
    }
    return _result.future.timeout(const Duration(minutes: 10));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_result.isCompleted) {
      _result.completeError(StateError('Sign-in canceled'));
    }
    await _subscription?.cancel();
    await _server.close(force: true);
  }
}
