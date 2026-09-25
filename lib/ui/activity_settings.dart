import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../backend/chat_backend.dart';
import '../models/user_activity.dart';
import '../services/activity_candidate.dart';
import '../services/lastfm_auth.dart';
import 'lastfm_connect_dialog.dart';

class ActivitySettingsPanel extends StatefulWidget {
  const ActivitySettingsPanel({required this.backend, super.key});
  final ChatBackend backend;
  @override
  State<ActivitySettingsPanel> createState() => _ActivitySettingsPanelState();
}

class _ActivitySettingsPanelState extends State<ActivitySettingsPanel> {
  bool _saving = false;
  Future<void> save(ActivitySettings value) async {
    setState(() => _saving = true);
    try {
      await widget.backend.updateActivitySettings(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not save activity preferences to this device’s secure storage.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> edit(String id, String name) async {
    final old = widget.backend.activitySettings.rules[id];
    final controller = TextEditingController(text: old?.name ?? name);
    var kind = old?.kind ?? ActivityKind.game;
    final value = await showDialog<ActivityRule>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: const Text('Program activity'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLength: 128,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              DropdownButton<ActivityKind>(
                value: kind,
                isExpanded: true,
                items: [
                  for (final value in ActivityKind.values)
                    DropdownMenuItem(value: value, child: Text(value.name)),
                ],
                onChanged: (value) => change(() => kind = value!),
              ),
              const Text(
                'This rule stays on this device. The executable path is never published.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(
                    context,
                    ActivityRule(name: controller.text.trim(), kind: kind),
                  );
                }
              },
              child: const Text('Allow'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value != null) {
      await save(
        widget.backend.activitySettings.copyWith(
          rules: {...widget.backend.activitySettings.rules, id: value},
        ),
      );
    }
  }

  Future<void> lastFm() async {
    final auth = LastFmAuth();
    final username = await showDialog<String>(
      context: context,
      builder: (_) => LastFmConnectDialog(auth: auth),
    );
    if (mounted && username != null) {
      await save(
        widget.backend.activitySettings.copyWith(
          lastFmUser: username,
          lastFmKey: auth.apiKey,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final settings = backend.activitySettings;
    final candidates = <String, ActivityCandidate>{
      for (final item in backend.detectedApplications) item.id: item,
    };
    for (final entry in settings.rules.entries) {
      candidates.putIfAbsent(
        entry.key,
        () => ActivityCandidate(
          id: entry.key,
          name: entry.value.name,
          running: false,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity sharing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Text(
          'Detection is local and optional. No process lists, paths, usage statistics or catalogue contributions are uploaded. Shared activity is public profile data, not encrypted; others may retain it. Invisible mode or disabling online presence suppresses sharing.',
        ),
        const Text(
          'Game/program, music, and Last.fm history are separate profile slots. Devices contribute independently; viewing includes activity shared by your other devices. Last.fm refreshes only while this app is open and you are online. Offline activities are hidden.',
        ),
        if (backend.supportsActivityDetection)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Detect games and music on this device'),
            value: settings.detect,
            onChanged: _saving
                ? null
                : (v) => save(settings.copyWith(detect: v)),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Share activity from this device'),
          value: settings.share,
          onChanged: _saving ? null : (v) => save(settings.copyWith(share: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show Last.fm last listened track on my profile'),
          subtitle: const Text(
            'Publish the last completed track, artist and album from this device. Requires a connected Last.fm account and activity sharing. Other devices can also contribute; hidden while offline.',
          ),
          value: settings.showLastFmRecent,
          onChanged: _saving
              ? null
              : (v) => save(settings.copyWith(showLastFmRecent: v)),
        ),
        if (backend.supportsActivityDetection)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Discord Rich Presence compatibility (preview)'),
            subtitle: const Text(
              'Linux local IPC only in this preview. Requires Discord to release its socket; abandoned sockets are recovered, but active listeners are never replaced. No join secrets or account access.',
            ),
            value: settings.rpc,
            onChanged: _saving ? null : (v) => save(settings.copyWith(rpc: v)),
          ),
        if (backend.activityWarning != null)
          Text(
            backend.activityWarning!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (settings.detect && candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No matching program yet. Scanning every 5 seconds. Add an executable below to classify it manually.',
            ),
          ),
        for (final item
            in backend.supportsActivityDetection
                ? candidates.values
                : <ActivityCandidate>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: item.iconBytes == null
                ? const Icon(Icons.apps)
                : Image.memory(item.iconBytes!, width: 32, height: 32),
            title: Text(
              settings.rules[item.id]?.name ?? item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${settings.rules[item.id]?.kind.name ?? item.kind?.name ?? "Unclassified — not shared"}${item.running ? "" : " · not running"}',
            ),
            onTap: _saving ? null : () => edit(item.id, item.name),
            trailing: Switch(
              value: settings.rules[item.id]?.allowed ?? (item.kind != null),
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v &&
                          item.kind == null &&
                          !settings.rules.containsKey(item.id)) {
                        edit(item.id, item.name);
                        return;
                      }
                      final previous = settings.rules[item.id];
                      save(
                        settings.copyWith(
                          rules: {
                            ...settings.rules,
                            item.id: ActivityRule(
                              name: previous?.name ?? item.name,
                              kind:
                                  previous?.kind ??
                                  item.kind ??
                                  ActivityKind.application,
                              allowed: v,
                            ),
                          },
                        ),
                      );
                    },
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            if (backend.supportsActivityDetection)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add program'),
                onPressed: _saving
                    ? null
                    : () async {
                        final result = await FilePicker.pickFiles(
                          dialogTitle: 'Choose a program executable',
                        );
                        final file = result?.files.single;
                        if (mounted && file?.path != null) {
                          await edit(file!.path!, file.name);
                        }
                      },
              ),
            TextButton.icon(
              icon: const Icon(Icons.music_note),
              label: Text(
                settings.lastFmUser.isEmpty
                    ? 'Connect Last.fm'
                    : 'Reconnect Last.fm (${settings.lastFmUser})',
              ),
              onPressed: _saving ? null : lastFm,
            ),
            if (settings.lastFmUser.isNotEmpty)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => save(
                        settings.copyWith(lastFmUser: '', lastFmKey: ''),
                      ),
                child: const Text('Disconnect Last.fm'),
              ),
          ],
        ),
        const Divider(),
      ],
    );
  }
}
