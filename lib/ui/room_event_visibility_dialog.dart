import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/room_event_visibility.dart';

Future<void> showRoomEventVisibility(
  BuildContext context,
  ChatBackend backend,
  String roomId,
) => showDialog<void>(
  context: context,
  builder: (_) => _EventVisibilityDialog(backend: backend, roomId: roomId),
);

class _EventVisibilityDialog extends StatefulWidget {
  const _EventVisibilityDialog({required this.backend, required this.roomId});
  final ChatBackend backend;
  final String roomId;
  @override
  State<_EventVisibilityDialog> createState() => _EventVisibilityDialogState();
}

class _EventVisibilityDialogState extends State<_EventVisibilityDialog> {
  late RoomEventVisibility _draft =
      widget.backend.preferences.roomEventVisibility;
  bool _global = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.backend.updatePreferences(
        widget.backend.preferences.copyWith(roomEventVisibility: _draft),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save display preferences. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Timeline events'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Only changes what you see. Preferences sync with your account. Messages, encryption notices and moderation actions remain visible.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Edit account defaults'),
              subtitle: const Text('Off: overrides for this room'),
              value: _global,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _global = value),
            ),
            for (final event in CosmeticRoomEvent.values)
              DropdownButtonFormField<String>(
                key: ValueKey('${_global}_${event.name}'),
                isExpanded: true,
                initialValue:
                    (_global
                            ? _draft.defaults[event.name]
                            : _draft.rooms[widget.roomId]?[event.name])
                        ?.toString() ??
                    'inherit',
                decoration: InputDecoration(labelText: event.label),
                items: [
                  DropdownMenuItem(
                    value: 'inherit',
                    child: Text(
                      _global ? 'Default (show)' : 'Use account default',
                    ),
                  ),
                  const DropdownMenuItem(value: 'true', child: Text('Show')),
                  const DropdownMenuItem(value: 'false', child: Text('Hide')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(
                        () => _draft = _draft.withValue(
                          _global ? null : widget.roomId,
                          event,
                          value == 'inherit' ? null : value == 'true',
                        ),
                      ),
              ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
