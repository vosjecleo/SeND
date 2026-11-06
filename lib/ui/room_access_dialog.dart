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
  late bool _direct = widget.backend.isRoomDirect(widget.roomId);
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
      if (_directory != data.discoverable) {
        final saved = await widget.backend.getRoomAccessSettings(widget.roomId);
        if (!mounted) return;
        if (saved.discoverable != _directory) {
          setState(
            () => _error =
                'The server did not keep the directory setting. Check your permissions and try again.',
          );
          return;
        }
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final access = <String, RoomAccessSettings>{};
    try {
      for (var i = 0; i < widget.children.length; i += 4) {
        await Future.wait(
          widget.children.skip(i).take(4).map((room) async {
            try {
              access[room.id] = await widget.backend.getRoomAccessSettings(
                room.id,
              );
            } catch (_) {
              /* Unavailable channels cannot be selected. */
            }
          }),
        );
        if (!mounted) return;
      }
      final selected = <String>{
        for (final room in widget.children)
          if (access[room.id]?.canEditAccess == true &&
              access[room.id]?.joinRule != 'invite')
            room.id,
      };
      final label = switch (_default) {
        'restricted' => 'Members of this server',
        'public' => 'Anyone',
        _ => 'Invite only',
      };
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) {
            final privateCount = selected
                .where((id) => access[id]?.joinRule == 'invite')
                .length;
            return AlertDialog(
              title: const Text('Update channel access?'),
              scrollable: true,
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set selected channels to "$label"? This will not join members or change history access.',
                    ),
                    const SizedBox(height: 12),
                    for (final room in widget.children)
                      CheckboxListTile(
                        dense: true,
                        title: Text(room.name),
                        subtitle: access[room.id]?.joinRule == 'invite'
                            ? const Text('Invite only')
                            : null,
                        secondary: access[room.id]?.joinRule == 'invite'
                            ? const Icon(Icons.lock_outline)
                            : null,
                        value: selected.contains(room.id),
                        onChanged: access[room.id]?.canEditAccess != true
                            ? null
                            : (value) => update(() {
                                if (value == true) {
                                  selected.add(room.id);
                                } else {
                                  selected.remove(room.id);
                                }
                              }),
                      ),
                    if (privateCount > 0)
                      Text(
                        'This changes access to $privateCount invite-only ${privateCount == 1 ? 'channel' : 'channels'}.',
                        style: TextStyle(
                          color: Theme.of(dialog).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialog, true),
                  child: Text(
                    'Apply to ${selected.length} ${selected.length == 1 ? 'channel' : 'channels'}',
                  ),
                ),
              ],
            );
          },
        ),
      );
      if (confirmed != true || !mounted) return;
      final failed = <String>[];
      for (final room in widget.children.where(
        (room) => selected.contains(room.id),
      )) {
        try {
          await widget.backend.setRoomAccess(
            room.id,
            _default,
            spaceId: widget.roomId,
          );
        } catch (_) {
          failed.add(room.name);
        }
        if (!mounted) return;
      }
      setState(
        () => _error = failed.isEmpty
            ? 'Access updated for ${selected.length} channels.'
            : 'Updated ${selected.length - failed.length} channels. Could not update: ${failed.join(', ')}.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not load channel access. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
              if (!widget.isSpace &&
                  widget.backend.canMarkRoomDirect(widget.roomId))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Treat as direct message'),
                  subtitle: const Text(
                    'This choice only affects your account.',
                  ),
                  value: _direct,
                  onChanged: _busy
                      ? null
                      : (value) async {
                          setState(() {
                            _busy = true;
                            _error = null;
                          });
                          try {
                            await widget.backend.setRoomDirect(
                              widget.roomId,
                              value,
                            );
                            if (mounted) setState(() => _direct = value);
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => _error =
                                    'Could not change room classification. Please retry.',
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                ),
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
                const Text('Listing a room doesn\'t change who can join it.'),
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
                  'Only affects future messages; missing encryption keys may still limit history.',
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
                  'Applies to everyone using SeND; channel settings override Space defaults. Other clients may still show these events.',
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
