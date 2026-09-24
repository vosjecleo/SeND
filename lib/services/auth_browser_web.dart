import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

class AuthBrowser {
  AuthBrowser._(this.redirect, this._window, this._channel) {
    unawaited(
      _result.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }
  final Uri redirect;
  final web.Window? _window;
  final web.BroadcastChannel _channel;
  final _result = Completer<Uri>();
  JSFunction? _listener;
  bool _closed = false;

  static Future<AuthBrowser> prepare(String nonce) async {
    // Must run directly from the user's click, before any network await, so
    // Safari permits the window. BroadcastChannel also supports standalone
    // PWA windows whose browser does not preserve window.opener.
    final popup = web.window.open('about:blank', 'deltiecord-sign-in');
    if (popup == null) {
      throw StateError('Allow the sign-in popup and try again.');
    }
    final channel = web.BroadcastChannel('deltiecord-auth');
    final browser = AuthBrowser._(
      Uri.base
          .resolve('/auth.html')
          .replace(queryParameters: {'session': nonce}),
      popup,
      channel,
    );
    void receive(web.MessageEvent event) {
      final data = event.data.dartify();
      if (data is! String) return;
      final uri = Uri.tryParse(data);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.origin != browser.redirect.origin ||
          uri.path != browser.redirect.path ||
          uri.queryParameters['session'] != nonce) {
        return;
      }
      if (!browser._result.isCompleted) browser._result.complete(uri);
    }

    browser._listener = receive.toJS;
    channel.addEventListener('message', browser._listener);
    return browser;
  }

  Future<Uri> authenticate(Uri authorization) async {
    if (_closed) throw StateError('Sign-in canceled');
    _window!.location.href = authorization.toString();
    return _result.future.timeout(const Duration(minutes: 10));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!_result.isCompleted) {
      _result.completeError(StateError('Sign-in canceled'));
    }
    _channel.removeEventListener('message', _listener);
    _channel.close();
    _window?.close();
  }
}
