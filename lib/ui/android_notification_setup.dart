import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend/chat_backend.dart';
import '../services/unified_push.dart';

/// Device-local choice, shared by onboarding and Notifications settings.
class AndroidNotificationSetup extends StatefulWidget {
  const AndroidNotificationSetup({
    required this.backend,
    this.onChanged,
    super.key,
  });
  final ChatBackend backend;
  final VoidCallback? onChanged;

  @override
  State<AndroidNotificationSetup> createState() =>
      _AndroidNotificationSetupState();
}

class _AndroidNotificationSetupState extends State<AndroidNotificationSetup> {
  String _choice = 'builtin';
  bool _busy = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final account = widget.backend.userId;
      if (account == null) return;
      final state = await UnifiedPushPlatform.instance.state(account);
      if (!mounted) return;
      setState(() {
        _choice = state.disabled
            ? 'off'
            : state.builtIn || state.distributor == null
            ? 'builtin'
            : 'unified';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not check notification settings. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final account = widget.backend.userId;
    if (account == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final platform = UnifiedPushPlatform.instance;
    try {
      if (_choice == 'off') {
        final current = await platform.state(account);
        try {
          if (current.endpoint case final endpoint?) {
            await widget.backend.removeUnifiedPushEndpoint(endpoint);
          }
        } finally {
          await platform.unregister(account);
        }
        if (mounted) {
          setState(() => _message = 'Background notifications are off.');
        }
        return;
      }
      final allowed = await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      if (allowed != true) {
        if (mounted) {
          setState(
            () => _message =
                'Allow notifications in Android settings, then try again.',
          );
        }
        return;
      }
      UnifiedPushState state;
      if (_choice == 'builtin') {
        state = await platform.enableBuiltIn(account);
      } else {
        final distributors = await platform.distributors();
        if (!mounted) return;
        if (distributors.isEmpty) {
          setState(
            () => _message = 'Install and open ntfy first, then try again.',
          );
          return;
        }
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Choose a notification app'),
            children: [
              for (final distributor in distributors)
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.pop(context, distributor.packageName),
                  child: Text(distributor.label),
                ),
            ],
          ),
        );
        if (selected == null) return;
        state = await platform.selectDistributor(selected, account);
      }
      state = await platform.waitForEndpoint(account, initialState: state);
      final endpoint = state.endpoint;
      if (endpoint == null) {
        if (mounted) {
          setState(
            () => _message =
                'Could not connect. Check your internet connection and try again.',
          );
        }
        return;
      }
      await widget.backend.setUnifiedPushEndpoint(endpoint);
      if (mounted) {
        setState(() => _message = 'Background notifications are on.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Could not finish notification setup. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) {
        widget.onChanged?.call();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey('notification-method-$_choice'),
        initialValue: _choice,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Notification delivery'),
        items: const [
          DropdownMenuItem(value: 'builtin', child: Text('Built-in')),
          DropdownMenuItem(value: 'unified', child: Text('UnifiedPush')),
          DropdownMenuItem(value: 'off', child: Text('Off')),
        ],
        onChanged: _busy
            ? null
            : (value) => setState(() {
                _choice = value!;
                _message = null;
              }),
      ),
      const SizedBox(height: 12),
      Text(switch (_choice) {
        'builtin' =>
          'No extra app needed. SeND keeps a quiet notification while listening for messages. '
              'Allow background battery use for reliable delivery. This may use more battery. '
              'Force-stopping SeND stops alerts until you reopen it.',
        'unified' =>
          'Use a notification app such as ntfy. Install and open it, then select '
              'https://push.deltie.net as its UnifiedPush server, or use a compatible server you trust. '
              'Allow that app to run in the background.',
        _ =>
          'You may miss messages while SeND is closed. You can change this in Settings > Notifications.',
      }),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: Text(_busy ? 'Please wait…' : 'Apply'),
          ),
          if (_choice == 'builtin')
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      try {
                        await UnifiedPushPlatform.instance
                            .openBatterySettings();
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _message =
                                'Open Android Settings and allow SeND to run in the background.',
                          );
                        }
                      }
                    },
              child: const Text('Battery settings'),
            ),
          if (_choice == 'unified')
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse('https://f-droid.org/packages/io.heckel.ntfy/'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Text('Get ntfy from F-Droid'),
            ),
        ],
      ),
      if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
    ],
  );
}
