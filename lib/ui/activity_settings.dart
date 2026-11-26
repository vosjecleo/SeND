import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../models/user_activity.dart';
import '../services/activity_candidate.dart';
import '../services/activity_discovery.dart';
import '../services/lastfm_auth.dart';
import 'lastfm_connect_dialog.dart';

String activitySharingHint(
  ActivityCandidate item,
  ActivitySettings settings, {
  required bool presenceVisible,
}) {
  final rule = settings.rules[item.id];
  if (!settings.detect) return 'App detection is off';
  if (!item.running) return 'Not running';
  if (isSpotifyCandidate(item) && !item.mediaSession) {
    return 'Shares music playback only';
  }
  if (rule?.allowed == false) return 'Sharing is off for this app';
  if (sharedActivityKind(item, rule) == null) {
    return 'Not recognized. Tap to choose how to share.';
  }
  if (!allowsActivitySharing(item, rule)) {
    return 'Not shared by default';
  }
  if (!settings.share) return 'Activity sharing is off on this device';
  if (!presenceVisible) {
    return 'Sharing is paused while your presence is hidden';
  }
  final kind = sharedActivityKind(item, rule)!;
  return switch (kind) {
    ActivityKind.game => 'Game · Allowed to share',
    ActivityKind.music => 'Music · Allowed to share',
    ActivityKind.application => 'App · Allowed to share',
  };
}

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
            content: Text('Couldn\'t save activity settings on this device.'),
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
          useLibreFm: false,
        ),
      );
    }
  }

  Future<void> libreFm() async {
    final controller = TextEditingController(
      text: widget.backend.activitySettings.libreFmUser,
    );
    final username = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link Libre.fm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 64,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Libre.fm username'),
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
              final user = controller.text.trim();
              if (user.isNotEmpty) Navigator.pop(context, user);
            },
            child: const Text('Link'),
          ),
        ],
      ),
    );
    // The closing dialog can still be painting the field during its animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (mounted && username != null) {
      await save(
        widget.backend.activitySettings.copyWith(
          libreFmUser: username,
          useLibreFm: true,
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
          'Shared activity is public, unencrypted and may be saved by others. Invisible mode or turning off online presence stops sharing.',
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
          title: Text(
            'Show ${settings.listeningProviderName} last listened track on my profile',
          ),
          subtitle: const Text(
            'Your last track stays visible offline. Turning this off only removes tracks shared by this device.',
          ),
          value: settings.showLastFmRecent,
          onChanged: _saving
              ? null
              : (v) => save(settings.copyWith(showLastFmRecent: v)),
        ),
        if (settings.useLibreFm)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Look up missing album covers'),
            subtitle: const Text(
              'Sends artist and album names to MusicBrainz and Cover Art Archive, not your username.',
            ),
            value: settings.lookupListeningArtwork,
            onChanged: _saving
                ? null
                : (v) => save(settings.copyWith(lookupListeningArtwork: v)),
          ),
        if (settings.lastFmUser.isNotEmpty || settings.libreFmUser.isNotEmpty)
          DropdownButtonFormField<bool>(
            key: ValueKey(settings.useLibreFm),
            initialValue: settings.useLibreFm,
            decoration: const InputDecoration(
              labelText: 'Listening history source',
            ),
            items: [
              DropdownMenuItem(
                value: false,
                enabled: settings.lastFmUser.isNotEmpty,
                child: const Text('Last.fm'),
              ),
              DropdownMenuItem(
                value: true,
                enabled: settings.libreFmUser.isNotEmpty,
                child: const Text('Libre.fm'),
              ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value != null) {
                      save(settings.copyWith(useLibreFm: value));
                    }
                  },
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
            TextButton.icon(
              icon: const Icon(Icons.music_note),
              label: Text(
                settings.libreFmUser.isEmpty
                    ? 'Link Libre.fm'
                    : 'Change Libre.fm (${settings.libreFmUser})',
              ),
              onPressed: _saving ? null : libreFm,
            ),
            if (settings.libreFmUser.isNotEmpty)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => save(
                        settings.copyWith(libreFmUser: '', useLibreFm: false),
                      ),
                child: const Text('Unlink Libre.fm'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (backend.supportsActivityDetection)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Discord Rich Presence compatibility (preview)'),
            subtitle: const Text(
              'Close Discord to let SeND receive game activity.',
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
              'No apps detected. Open the game or add its executable.',
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
              sharedActivityName(item, settings.rules[item.id]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              activitySharingHint(
                item,
                settings,
                presenceVisible:
                    backend.preferences.sharePresence &&
                    backend.presenceMode != PresenceMode.invisible,
              ),
            ),
            onTap: _saving || isSpotifyCandidate(item)
                ? null
                : () => edit(item.id, item.name),
            trailing: Switch(
              value: allowsActivitySharing(item, settings.rules[item.id]),
              onChanged:
                  _saving || (isSpotifyCandidate(item) && !item.mediaSession)
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
        const Divider(),
      ],
    );
  }
}
