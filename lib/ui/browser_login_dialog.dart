import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../models/login_methods.dart';

class BrowserLoginDialog extends StatefulWidget {
  const BrowserLoginDialog({
    super.key,
    required this.backend,
    required this.homeserver,
  });
  final ChatBackend backend;
  final String homeserver;
  @override
  State<BrowserLoginDialog> createState() => _BrowserLoginDialogState();
}

class _BrowserLoginDialogState extends State<BrowserLoginDialog> {
  late final _server = TextEditingController(text: widget.homeserver);
  LoginMethods? _methods;
  String? _error;
  bool _loading = false;

  Future<void> _discover() async {
    final uri = Uri.tryParse(_server.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _error = 'Enter an HTTPS homeserver address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _methods = null;
    });
    try {
      final methods = await widget.backend.discoverLoginMethods(uri);
      if (mounted) setState(() => _methods = methods);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not discover sign-in methods. Check the server address and connection.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login(bool oidc) async {
    final methods = _methods;
    if (methods == null) return;
    // Start before awaiting anything: iOS needs the button's user gesture.
    final login = widget.backend.loginWithBrowser(
      methods.homeserver,
      oidc: oidc,
    );
    setState(() => _loading = true);
    await login;
    if (!mounted) return;
    if (widget.backend.status == SessionStatus.signedIn) {
      Navigator.pop(context);
    } else {
      setState(() {
        _loading = false;
        _error = widget.backend.error ?? 'Sign-in did not complete.';
      });
    }
  }

  @override
  void dispose() {
    if (_loading && widget.backend.status == SessionStatus.signingIn) {
      unawaited(widget.backend.cancelBrowserLogin());
    }
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Browser sign-in'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _server,
              enabled: !_loading,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Homeserver'),
              onChanged: (_) => setState(() => _methods = null),
            ),
            const SizedBox(height: 12),
            const Text(
              'Use the sign-in methods offered by your homeserver. You will still need to verify this device or recover your encryption keys afterwards.',
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!),
              ),
            if (_methods case final methods?) ...[
              if (methods.oidc)
                FilledButton(
                  onPressed: _loading ? null : () => _login(true),
                  child: const Text('Continue with OIDC'),
                ),
              if (methods.sso)
                OutlinedButton(
                  onPressed: _loading ? null : () => _login(false),
                  child: const Text('Continue with SSO'),
                ),
              if (!methods.oidc && !methods.sso)
                Text(
                  methods.password
                      ? 'This server currently offers password sign-in only. Use the main sign-in form.'
                      : 'This server does not advertise a supported interactive sign-in method.',
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (_loading && widget.backend.status == SessionStatus.signingIn)
        TextButton(
          onPressed: widget.backend.cancelBrowserLogin,
          child: const Text('Cancel sign-in'),
        ),
      TextButton(
        onPressed: _loading ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
      TextButton(
        onPressed: _loading ? null : _discover,
        child: const Text('Check server'),
      ),
    ],
  );
}
