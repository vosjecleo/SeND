import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';

enum _SettingsPage {
  account,
  devices,
  encryption,
  audioVideo,
  notifications,
  privacy,
  appearance,
  accessibility,
  storage,
  shortcuts,
  advanced,
  about,
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
  void initState() {
    super.initState();
    backend.refreshAudioInputs();
    backend.refreshDevices();
    backend.refreshProfile();
  }

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
    _SettingsPage.account => _account(),
    _SettingsPage.devices => _devices(),
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
        title: const Text('Desktop notifications'),
        subtitle: const Text('Notify for new Matrix messages.'),
        value: backend.preferences.notificationsEnabled,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(notificationsEnabled: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Show message content'),
        subtitle: const Text(
          'Include decrypted message previews in notifications.',
        ),
        value: backend.notificationPreviewsEnabled,
        onChanged: backend.setNotificationPreviewsEnabled,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Notification sound'),
        subtitle: const Text(
          'Allow the desktop notification service to play sound.',
        ),
        value: backend.preferences.notificationSound,
        onChanged: (value) => backend.updatePreferences(
          backend.preferences.copyWith(notificationSound: value),
        ),
      ),
    ]),
    _SettingsPage.privacy => _privacy(),
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
      _value('Deltiecord', 'v0.4.0'),
      _value('Session', backend.status.name),
      _value('Connection', backend.connectionStatus.name),
      _value('Voice', backend.voiceConnectionStatus.name),
      _value('Selected room', backend.selectedRoom?.id ?? 'None'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () {
          final report = [
            'Deltiecord v0.4.0',
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
    _SettingsPage.about => _section('About Deltiecord', [
      const Text(
        'Deltiecord v0.4.1\n'
        'A compact, old-school desktop Matrix client built with Flutter.',
      ),
      const SizedBox(height: 12),
      const Text(
        'Matrix connectivity and encryption use matrix-dart-sdk. MatrixRTC, '
        'media_kit, Flutter WebRTC, Flutter Quill, GIPHY, Element, and '
        'FluffyChat informed or support parts of the implementation.',
      ),
      const SizedBox(height: 12),
      const SelectableText(
        'Full acknowledgements and upstream license links are in CREDITS.md.',
      ),
      const SizedBox(height: 20),
      const Text(
        'Made for dense desktops, strange little computers, and friends.',
      ),
    ]),
  };

  Widget _account() => _section('Account', [
    Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 38,
          backgroundImage: backend.profileAvatarBytes == null
              ? null
              : MemoryImage(backend.profileAvatarBytes!),
          child: backend.profileAvatarBytes == null
              ? const Icon(Icons.person, size: 34)
              : null,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                backend.profileDisplayName ??
                    backend.userId ??
                    'Matrix account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(backend.userId ?? 'Unavailable'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _editDisplayName,
                    child: const Text('Change display name'),
                  ),
                  OutlinedButton(
                    onPressed: _pickAvatar,
                    child: const Text('Change picture'),
                  ),
                  if (backend.profileAvatarBytes != null)
                    TextButton(
                      onPressed: () => _runSettingAction(
                        () => backend.setProfileAvatar(null),
                      ),
                      child: const Text('Remove picture'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
    const Divider(height: 28),
    _value('Homeserver', backend.homeserver?.toString() ?? 'Unavailable'),
    _value('Device ID', backend.deviceId ?? 'Unavailable'),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      onPressed: backend.logout,
      icon: const Icon(Icons.logout),
      label: const Text('Log out'),
    ),
    const SizedBox(height: 28),
    Text(
      'Danger zone',
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
    const Text(
      'Permanently deactivate this Matrix account and request data erasure.',
    ),
    OutlinedButton.icon(
      onPressed: _confirmDeleteAccount,
      icon: const Icon(Icons.delete_forever_outlined),
      label: const Text('Delete account'),
    ),
  ]);

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
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: preferences.fontFamily,
        decoration: const InputDecoration(
          labelText: 'Interface font',
          border: OutlineInputBorder(),
        ),
        items:
            const [
                  'System',
                  'Noto Sans',
                  'DejaVu Sans',
                  'Liberation Sans',
                  'monospace',
                ]
                .map((font) => DropdownMenuItem(value: font, child: Text(font)))
                .toList(growable: false),
        onChanged: (font) {
          if (font != null) {
            backend.updatePreferences(preferences.copyWith(fontFamily: font));
          }
        },
      ),
      const SizedBox(height: 16),
      const Text('Accent colour'),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children:
            const [
                  0xff6975d9,
                  0xff9b6bd3,
                  0xff3f94a8,
                  0xff4f9b68,
                  0xffc47a45,
                  0xffba6074,
                ]
                .map((color) {
                  final selected = preferences.accentColor == color;
                  return Tooltip(
                    message:
                        '#${color.toRadixString(16).substring(2).toUpperCase()}',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => backend.updatePreferences(
                        preferences.copyWith(accentColor: color),
                      ),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check, size: 17)
                            : null,
                      ),
                    ),
                  );
                })
                .toList(growable: false),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Native title bar'),
        subtitle: const Text('Show GTK window decorations on Linux.'),
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

  Widget _privacy() {
    final preferences = backend.preferences;
    return _section('Privacy & presence', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send read receipts'),
        subtitle: const Text('Let rooms know which messages you have read.'),
        value: preferences.sendReadReceipts,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sendReadReceipts: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Send typing notifications'),
        value: preferences.sendTypingNotifications,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sendTypingNotifications: value),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Share online presence'),
        subtitle: const Text(
          'Turning this off reports this device as offline.',
        ),
        value: preferences.sharePresence,
        onChanged: (value) => backend.updatePreferences(
          preferences.copyWith(sharePresence: value),
        ),
      ),
    ]);
  }

  Widget _devices() => _section('Devices', [
    Row(
      children: [
        const Expanded(
          child: Text(
            'Matrix sessions currently associated with this account.',
          ),
        ),
        IconButton(
          tooltip: 'Refresh devices',
          onPressed: backend.devicesLoading ? null : backend.refreshDevices,
          icon: backend.devicesLoading
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
    if (!backend.devicesLoading && backend.deviceSessions.isEmpty)
      const Text('No device information is available.')
    else
      for (final device in backend.deviceSessions)
        Card(
          child: ListTile(
            leading: Icon(
              device.current ? Icons.computer : Icons.devices_other,
            ),
            title: Text(
              '${device.displayName}${device.current ? ' (this device)' : ''}',
            ),
            subtitle: Text(
              [
                device.id,
                if (device.lastSeenAt != null)
                  'Last seen ${_formatDeviceTime(device.lastSeenAt!)}',
                if (device.lastSeenIp != null) device.lastSeenIp!,
              ].join(' · '),
            ),
            trailing: device.current
                ? null
                : IconButton(
                    tooltip: 'Remove device',
                    onPressed: () => _confirmRemoveDevice(device),
                    icon: const Icon(Icons.logout),
                  ),
          ),
        ),
    const Text(
      'Session removal requires interactive Matrix authentication and will be '
      'added with the permission-aware management pass in v0.5.',
    ),
  ]);

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

  Future<void> _editDisplayName() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) =>
          _DisplayNameDialog(initialValue: backend.profileDisplayName ?? ''),
    );
    if (value?.isNotEmpty == true) {
      await _runSettingAction(() => backend.setProfileDisplayName(value!));
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? await result.xFiles.single.readAsBytes();
    await _runSettingAction(
      () => backend.setProfileAvatar(
        bytes,
        fileName: file.name,
        mimeType: lookupMimeType(file.name, headerBytes: bytes) ?? 'image/png',
      ),
    );
  }

  Future<String?> _askForPassword(String title, String warning) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) =>
          _PasswordPromptDialog(title: title, warning: warning),
    );
    return password?.isNotEmpty == true ? password : null;
  }

  Future<void> _confirmRemoveDevice(DeviceSessionSummary device) async {
    final password = await _askForPassword(
      'Remove ${device.displayName}?',
      'This signs that device out and removes its Matrix device keys. '
          'Encrypted history stored only on that device may become unavailable.',
    );
    if (password != null) {
      await _runSettingAction(() => backend.removeDevice(device.id, password));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final password = await _askForPassword(
      'Permanently delete account?',
      'This deactivates ${backend.userId}, signs out all devices, and requests '
          'server-side data erasure. This cannot be undone.',
    );
    if (password != null) {
      await _runSettingAction(() => backend.deleteAccount(password));
    }
  }

  Future<void> _runSettingAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exception.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }
}

class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change display name'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Display name'),
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.title, required this.warning});

  final String title;
  final String warning;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.warning),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Matrix account password',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: Navigator.of(context).pop,
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Confirm'),
      ),
    ],
  );
}

IconData _iconFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => Icons.person_outline,
  _SettingsPage.devices => Icons.devices_outlined,
  _SettingsPage.encryption => Icons.shield_outlined,
  _SettingsPage.audioVideo => Icons.headset_mic_outlined,
  _SettingsPage.notifications => Icons.notifications_outlined,
  _SettingsPage.privacy => Icons.visibility_outlined,
  _SettingsPage.appearance => Icons.palette_outlined,
  _SettingsPage.accessibility => Icons.accessibility_new,
  _SettingsPage.storage => Icons.storage_outlined,
  _SettingsPage.shortcuts => Icons.keyboard_outlined,
  _SettingsPage.advanced => Icons.terminal,
  _SettingsPage.about => Icons.info_outline,
};

String _labelFor(_SettingsPage page) => switch (page) {
  _SettingsPage.account => 'Account',
  _SettingsPage.devices => 'Devices',
  _SettingsPage.encryption => 'Encryption',
  _SettingsPage.audioVideo => 'Audio & video',
  _SettingsPage.notifications => 'Notifications',
  _SettingsPage.privacy => 'Privacy',
  _SettingsPage.appearance => 'Appearance',
  _SettingsPage.accessibility => 'Accessibility',
  _SettingsPage.storage => 'Storage',
  _SettingsPage.shortcuts => 'Shortcuts',
  _SettingsPage.advanced => 'Advanced',
  _SettingsPage.about => 'About',
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

String _formatDeviceTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
