import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import '../services/lastfm_auth.dart';

class LastFmConnectDialog extends StatefulWidget {
  const LastFmConnectDialog({required this.auth, super.key});
  final LastFmAuth auth;
  @override
  State<LastFmConnectDialog> createState() => _LastFmConnectDialogState();
}

class _LastFmConnectDialogState extends State<LastFmConnectDialog> {
  String? _token, _error;
  bool _busy = false;
  bool _opened = false;
  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_token == null) {
        final token = await widget.auth.begin();
        if (!mounted) return;
        setState(() => _token = token);
        // Safari requires the window-opening call to occur directly in a user
        // gesture, not after the asynchronous request-token exchange.
        if (kIsWeb) return;
      }
      if (!_opened) {
        if (!await launchUrl(
          widget.auth.authorizationUrl(_token!),
          mode: LaunchMode.externalApplication,
          webOnlyWindowName: '_blank',
        )) {
          throw const LastFmAuthError(
            'Could not open your browser. Please try again.',
          );
        }
        if (mounted) setState(() => _opened = true);
      } else {
        final user = await widget.auth.finish(_token!);
        if (mounted) Navigator.pop(context, user);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is LastFmAuthError
              ? error.message
              : 'Could not connect to Last.fm. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Connect Last.fm'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            !widget.auth.configured
                ? 'Browser linking needs SeND’s own Last.fm application registration. It is not configured in this local preview. You do not need to create an API key. Local music detection still works without Last.fm.'
                : _token == null
                ? 'Sign in and approve SeND on Last.fm in your browser. We read your public now-playing feed and, if enabled, your last completed track. We do not scrobble, change your library, or keep your password. You control publication through Activity settings.'
                : 'Approve SeND in your browser, then finish linking here. Activity sharing remains controlled by your Activity settings.',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (widget.auth.configured)
        FilledButton(
          onPressed: _busy ? null : _connect,
          child: Text(
            _busy
                ? 'Connecting…'
                : _token == null && kIsWeb
                ? 'Prepare sign-in'
                : !_opened
                ? 'Open Last.fm'
                : 'Finish linking',
          ),
        ),
    ],
  );
}
