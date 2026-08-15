import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';

enum _SettingsPage {
  account,
  devices,
  encryption,
  audioVideo,
  notifications,
  appearance,
  accessibility,
  storage,
  shortcuts,
  advanced,
}

Future<void> showDeltiecordSettings(
  BuildContext context,
  ChatBackend backend,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => _SettingsScreen(backend: backend),
    fullscreenDialog: true,
  ),
);

class _SettingsScreen extends StatefulWidget {
  const _SettingsScreen({required this.backend});

  final ChatBackend backend;

  @override
  State<_SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<_SettingsScreen> {
  _SettingsPage _page = _SettingsPage.account;

  ChatBackend get backend => widget.backend;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: backend,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          tooltip: 'Close settings',
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.close),
        ),
      ),
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: ListView(
              padding: const EdgeInsets.all(10),
              children: [
                for (final page in _SettingsPage.values)
                  ListTile(
                    dense: true,
                    selected: _page == page,
                    leading: Icon(_iconFor(page), size: 19),
                    title: Text(_labelFor(page)),
                    onTap: () => setState(() => _page = page),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 22, 32, 40),
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: _pageBody(),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _pageBody() => switch (_page) {
    _SettingsPage.account => _section('Account', [
      _value('Matrix ID', backend.userId ?? 'Unavailable'),
      _value('Homeserver', backend.homeserver?.toString() ?? 'Unavailable'),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: backend.logout,
        icon: const Icon(Icons.logout),
        label: const Text('Log out'),
      ),
    ]),
    _SettingsPage.devices => _section('Devices', [
      _value('This device', 'Deltiecord Desktop'),
      _value('Device ID', backend.deviceId ?? 'Unavailable'),
      const Text(
        'Full device-session management will gain permission-aware removal '
        'controls during v0.5. Encryption verification is available now.',
      ),
    ]),
    _SettingsPage.encryption => _section('Encryption & recovery', [
      _value('Status', _encryptionLabel(backend.encryptionSetup.status)),
      _value(
        'Encrypted key backup',
        backend.encryptionSetup.keyBackupEnabled ? 'Enabled' : 'Not configured',
      ),
      _value(
        'This device',
        backend.encryptionSetup.deviceVerified ? 'Verified' : 'Not verified',
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => showSecurityCenter(context, backend),
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Open encryption & recovery'),
      ),
    ]),
    _SettingsPage.audioVideo => _section('Audio & video', [
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: backend.selectedAudioInputId,
              decoration: const InputDecoration(
                labelText: 'Microphone',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('System default'),
                ),
                for (final input in backend.audioInputs)
                  DropdownMenuItem(value: input.id, child: Text(input.label)),
              ],
              onChanged: backend.selectAudioInput,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Refresh microphones',
            onPressed: backend.refreshAudioInputs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('Camera controls appear when video calling is enabled.'),
    ]),
    _SettingsPage.notifications => _section('Notifications', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show message content'),
        subtitle: const Text(
          'Include decrypted message previews in notifications.',
        ),
        value: backend.notificationPreviewsEnabled,
        onChanged: backend.setNotificationPreviewsEnabled,
      ),
    ]),
    _SettingsPage.appearance => _appearance(),
    _SettingsPage.accessibility => _accessibility(),
    _SettingsPage.storage => _section('Storage', [
      const Text(
        'Encrypted session data, room keys, thumbnails, and timeline caches are '
        'stored in Deltiecord’s private per-user application-data directory.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Cache inspection and selective cleanup are being hardened before '
        'destructive controls are exposed.',
      ),
    ]),
    _SettingsPage.shortcuts => _section('Keyboard shortcuts', [
      _shortcut('Focus message composer', 'Any printable key'),
      _shortcut('Send message', 'Enter'),
      _shortcut('New line', 'Shift + Enter'),
      _shortcut('Paste attachment', 'Ctrl + V'),
      _shortcut('Open settings', 'Ctrl + ,'),
      _shortcut('Close dialog / menu', 'Escape'),
    ]),
    _SettingsPage.advanced => _section('Advanced diagnostics', [
      _value('Deltiecord', 'v0.4 development'),
      _value('Session', backend.status.name),
      _value('Voice', backend.voiceConnectionStatus.name),
      _value('Selected room', backend.selectedRoom?.id ?? 'None'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () {
          final report = [
            'Deltiecord v0.4 development',
            'session=${backend.status.name}',
            'homeserver=${backend.homeserver}',
            'device=${backend.deviceId}',
            'voice=${backend.voiceConnectionStatus.name}',
          ].join('\n');
          Clipboard.setData(ClipboardData(text: report));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Safe diagnostics copied')),
          );
        },
        icon: const Icon(Icons.copy),
        label: const Text('Copy safe diagnostics'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Diagnostics deliberately exclude access tokens, recovery material, '
        'decrypted messages, and media encryption keys.',
      ),
    ]),
  };

  Widget _appearance() {
    final preferences = backend.preferences;
    return _section('Appearance', [
      SegmentedButton<InterfaceDensity>(
        segments: const [
          ButtonSegment(
            value: InterfaceDensity.compact,
            label: Text('Compact'),
          ),
          ButtonSegment(value: InterfaceDensity.cozy, label: Text('Cozy')),
        ],
        selected: {preferences.density},
        onSelectionChanged: (value) => backend.updatePreferences(
          preferences.copyWith(density: value.first),
        ),
      ),
      const SizedBox(height: 20),
      Text('Font scale — ${(preferences.fontScale * 100).round()}%'),
      Slider(
        value: preferences.fontScale,
        min: 0.8,
        max: 1.4,
        divisions: 6,
        label: '${(preferences.fontScale * 100).round()}%',
        onChanged: (value) =>
            backend.updatePreferences(preferences.copyWith(fontScale: value)),
      ),
      Text('Room panel — ${preferences.roomPanelWidth.round()} px'),
      Slider(
        value: preferences.roomPanelWidth,
        min: 220,
        max: 420,
        divisions: 10,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(roomPanelWidth: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Autoplay GIFs'),
        value: preferences.autoplayGifs,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(autoplayGifs: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Native title bar'),
        subtitle: const Text('Applied to new windows after restart.'),
        value: preferences.showNativeTitleBar,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(showNativeTitleBar: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Remember window size and position'),
        value: preferences.rememberWindowState,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(rememberWindowState: value),
        ),
      ),
    ]);
  }

  Widget _accessibility() {
    final preferences = backend.preferences;
    return _section('Accessibility', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Reduce motion'),
        subtitle: const Text('Avoid non-essential interface animation.'),
        value: preferences.reducedMotion,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(reducedMotion: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Higher contrast'),
        subtitle: const Text('Strengthen panel borders and text contrast.'),
        value: preferences.highContrast,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(highContrast: value),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'All primary workflows remain keyboard reachable and use visible focus '
        'indicators. Deltiecord does not communicate status by colour alone.',
      ),
    ]);
  }

  Widget _section(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 20),
      ...children.map(
        (child) =>
            Padding(padding: const EdgeInsets.only(bottom: 8), child: child),
      ),
    ],
  );

  Widget _value(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 170, child: Text(label)),
      Expanded(child: SelectableText(value)),
    ],
  );

  Widget _shortcut(String action, String keys) => _value(action, keys);
}

IconData _iconFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => Icons.person_outline,
  _SettingsPage.devices => Icons.devices_outlined,
  _SettingsPage.encryption => Icons.shield_outlined,
  _SettingsPage.audioVideo => Icons.headset_mic_outlined,
  _SettingsPage.notifications => Icons.notifications_outlined,
  _SettingsPage.appearance => Icons.palette_outlined,
  _SettingsPage.accessibility => Icons.accessibility_new,
  _SettingsPage.storage => Icons.storage_outlined,
  _SettingsPage.shortcuts => Icons.keyboard_outlined,
  _SettingsPage.advanced => Icons.terminal,
};

String _labelFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => 'Account',
  _SettingsPage.devices => 'Devices',
  _SettingsPage.encryption => 'Encryption',
  _SettingsPage.audioVideo => 'Audio & video',
  _SettingsPage.notifications => 'Notifications',
  _SettingsPage.appearance => 'Appearance',
  _SettingsPage.accessibility => 'Accessibility',
  _SettingsPage.storage => 'Storage',
  _SettingsPage.shortcuts => 'Shortcuts',
  _SettingsPage.advanced => 'Advanced',
};

String _encryptionLabel(EncryptionSetupStatus status) => switch (status) {
  EncryptionSetupStatus.ready => 'Protected',
  EncryptionSetupStatus.loading => 'Checking…',
  EncryptionSetupStatus.needsRecovery => 'Recovery required',
  EncryptionSetupStatus.needsRepair => 'Needs repair',
  EncryptionSetupStatus.needsSetup => 'Not configured',
  EncryptionSetupStatus.unavailable => 'Unavailable',
  EncryptionSetupStatus.error => 'Error',
};
