import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/space_administration.dart';
import '../models/room_event_visibility.dart';

Future<void> showRoomAccessDialog(
  BuildContext context,
  ChatBackend backend,
  String roomId, {
  String? spaceId,
  bool isSpace = false,
  List<AdministrationRoom> children = const [],
}) => showDialog<void>(
  context: context,
  builder: (_) => _RoomAccessDialog(
    backend: backend,
    roomId: roomId,
    spaceId: spaceId,
    isSpace: isSpace,
    children: children,
  ),
);

class _RoomAccessDialog extends StatefulWidget {
  const _RoomAccessDialog({
    required this.backend,
    required this.roomId,
    required this.spaceId,
    required this.isSpace,
    required this.children,
  });
  final ChatBackend backend;
  final String roomId;
  final String? spaceId;
  final bool isSpace;
  final List<AdministrationRoom> children;
  @override
  State<_RoomAccessDialog> createState() => _RoomAccessDialogState();
}

class _RoomAccessDialogState extends State<_RoomAccessDialog> {
  RoomAccessSettings? _data;
  String? _error;
  bool _busy = false;
  String _access = 'invite', _history = 'shared', _default = 'invite';
  bool _directory = false;
  Map<String, bool> _events = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.backend.getRoomAccessSettings(widget.roomId);
      if (!mounted) return;
      setState(() {
        _data = data;
        _access = data.joinRule;
        _history = data.historyVisibility;
        _directory = data.discoverable;
        _default = data.defaultChannelAccess;
        _events = {...data.eventVisibility};
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load settings. Check your connection and room access.',
        );
      }
    }
  }

  Future<void> _save() async {
    final data = _data!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_access != data.joinRule) {
        await widget.backend.setRoomAccess(
          widget.roomId,
          _access,
          spaceId: widget.spaceId,
        );
      }
      if (_history != data.historyVisibility) {
        await widget.backend.setRoomHistoryVisibility(widget.roomId, _history);
      }
      if (_directory != data.discoverable) {
        await widget.backend.setRoomDiscoverable(widget.roomId, _directory);
      }
      if (data.canEditPolicy) {
        await widget.backend.setSpacePolicy(
          widget.roomId,
          defaultChannelAccess: _default,
          eventVisibility: _events,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Some settings could not be saved. Check permissions and room-version support. Successful changes remain applied; retry is safe.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applyChildren() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace access rules for existing channels?'),
        content: Text(
          'Apply "$_default" to all ${widget.children.length} listed channels? This includes private channels. Cancel to preserve private exceptions and edit channels individually instead. This does not join members automatically or change history visibility.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply to all'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final failed = <String>[];
    for (final room in widget.children) {
      try {
        await widget.backend.setRoomAccess(
          room.id,
          _default,
          spaceId: widget.roomId,
        );
      } catch (_) {
        failed.add(room.name);
      }
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = failed.isEmpty
            ? 'Access updated for all listed channels.'
            : 'Failed: ${failed.join(', ')}. Other channels were updated.';
      });
    }
  }

  Widget _choice(
    String label,
    String value,
    Map<String, String> options,
    bool enabled,
    ValueChanged<String> changed,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: {...options, if (!options.containsKey(value)) value: value}
              .entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _busy || !enabled
              ? null
              : (value) {
                  if (value != null) setState(() => changed(value));
                },
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AlertDialog(
      title: Text(
        widget.isSpace
            ? 'Space access and timeline'
            : 'Channel access and timeline',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) Text(_error!),
              if (data == null)
                TextButton(onPressed: _load, child: const Text('Load settings'))
              else ...[
                Text('Room version ${data.roomVersion}'),
                _choice(
                  'Who can join?',
                  _access,
                  {
                    'invite': 'Invite only',
                    'public': 'Anyone',
                    'knock': 'Request to join',
                    if (widget.spaceId != null && !widget.isSpace)
                      'restricted': 'Members of this Space',
                  },
                  data.canEditAccess,
                  (v) => _access = v,
                ),
                const Text(
                  'Access and directory listing are separate. Space membership allows joining; it does not automatically join every channel.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('List in the public room directory'),
                  value: _directory,
                  onChanged: _busy || !data.canEditAccess
                      ? null
                      : (v) => setState(() => _directory = v),
                ),
                _choice(
                  'Who may read history?',
                  _history,
                  const {
                    'joined': 'Since joining',
                    'invited': 'Since invitation',
                    'shared': 'All joined members',
                    'world_readable': 'Everyone (public history)',
                  },
                  data.canEditHistory,
                  (v) => _history = v,
                ),
                const Text(
                  'History changes affect future events. Encryption key availability can further limit readable history.',
                ),
                if (widget.isSpace) ...[
                  _choice(
                    'Default access for new channels',
                    _default,
                    const {
                      'invite': 'Invite only',
                      'restricted': 'Members of this Space',
                      'public': 'Anyone',
                    },
                    data.canEditPolicy,
                    (v) => _default = v,
                  ),
                  OutlinedButton(
                    onPressed:
                        _busy || !data.canEditAccess || widget.children.isEmpty
                        ? null
                        : _applyChildren,
                    child: const Text('Apply access to existing channels…'),
                  ),
                ],
                const Divider(),
                Text(
                  'Shared timeline visibility',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Applies to all Deltiecord members; channel settings override Space defaults. Other clients may still show these events. Messages, security and moderation events cannot be hidden here.',
                ),
                for (final event in CosmeticRoomEvent.values)
                  _choice(
                    event.label,
                    _events[event.name]?.toString() ?? 'inherit',
                    const {
                      'inherit': 'Inherit',
                      'true': 'Show',
                      'false': 'Hide',
                    },
                    data.canEditPolicy,
                    (v) {
                      if (v == 'inherit') {
                        _events.remove(event.name);
                      } else {
                        _events[event.name] = v == 'true';
                      }
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: data == null || _busy ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
