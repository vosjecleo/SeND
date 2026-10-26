import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend/chat_backend.dart';
import '../services/unified_push.dart';
import '../services/browser_lifecycle.dart' as browser;

/// Only fixed diagnostic fields go in a report. Endpoints and exception text
/// can contain push capabilities and must not be copied into support messages.
String notificationStateReport(UnifiedPushState s) {
  String time(DateTime? value) => value?.toLocal().toString() ?? 'Never';
  String stage(String? value) =>
      value != null && RegExp(r'^[a-zA-Z0-9_. -]{1,100}$').hasMatch(value)
      ? value
      : 'Unknown';
  return [
    'Delivery method: ${stage(s.distributor)}',
    'Disabled: ${s.disabled}',
    'System notification permission: ${s.notificationsAllowed == null
        ? 'Unknown'
        : s.notificationsAllowed!
        ? 'Allowed'
        : 'Blocked'}',
    'Endpoint saved: ${s.registered}',
    'Registration: ${stage(s.registrationStage)}',
    'Registration error: ${s.error != null}',
    'Matrix pusher: ${stage(s.lastPusherResult)}',
    'Pusher checked: ${time(s.lastPusherVerification)}',
    'Connection: ${stage(s.connection)}',
    'Last push received: ${time(s.lastMessageReceived)}',
    'Last notification posted: ${time(s.lastNotificationPosted)}',
    'Background worker: ${stage(s.lastWorkerResult)}',
    'Test sent: ${time(s.lastTestRequest)}',
    'Test received: ${time(s.lastTestReceived)}',
    'Test result: ${stage(s.lastTestResult)}',
  ].join('\n');
}

class NotificationDiagnostics extends StatefulWidget {
  const NotificationDiagnostics({super.key, required this.backend});
  final ChatBackend backend;
  @override
  State<NotificationDiagnostics> createState() =>
      _NotificationDiagnosticsState();
}

class _NotificationDiagnosticsState extends State<NotificationDiagnostics> {
  String _report = 'No test run yet.';
  bool _busy = false;
  Future<void> _run({bool send = false, bool local = false}) async {
    setState(() => _busy = true);
    final lines = <String>[];
    try {
      if (local) {
        await widget.backend.testSystemNotification();
        lines.add('System notification requested. Check whether it appeared.');
      } else if (kIsWeb) {
        if (send) await browser.testBrowserPush();
        lines.add(await browser.browserPushDiagnostics());
      } else if (UnifiedPushPlatform.instance.supported) {
        final id = widget.backend.userId;
        if (id == null) throw StateError('Not logged in');
        final platform = UnifiedPushPlatform.instance;
        if (send) {
          try {
            await platform.testPush(id);
          } catch (_) {
            lines.add('Push test did not finish. See the stages below.');
          }
        }
        final state = await platform.state(id);
        lines.add(notificationStateReport(state));
        if (send && state.lastTestResult == 'receiver_verified') {
          await widget.backend.testSystemNotification();
          lines.add(
            'Android received the push. A test notification was requested.',
          );
        }
      } else {
        lines.add('Desktop notifications are delivered while SeND is running.');
      }
    } catch (_) {
      lines.add(
        'The check failed. Check your connection and notification permissions.',
      );
    }
    if (!mounted) return;
    setState(() {
      _report = lines.join('\n\n');
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Test delivery without sending a chat message. Tests do not check message decryption. For that, ask someone to send an encrypted message while SeND is closed.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (kIsWeb || UnifiedPushPlatform.instance.supported)
            OutlinedButton(
              onPressed: _busy ? null : () => _run(send: true),
              child: const Text('Test push delivery'),
            ),
          if (!kIsWeb)
            OutlinedButton(
              onPressed: _busy ? null : () => _run(local: true),
              child: const Text('Test system notification'),
            ),
          TextButton(
            onPressed: _busy ? null : _run,
            child: const Text('Refresh diagnostics'),
          ),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: _report)),
            child: const Text('Copy report'),
          ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      const SizedBox(height: 12),
      SelectableText(_report),
      const SizedBox(height: 12),
      const Text(
        'Push tests are limited to one per minute on Android. Reports omit your private push address and message content.',
      ),
    ],
  );
}
