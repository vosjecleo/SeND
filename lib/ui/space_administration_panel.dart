import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/space_administration.dart';
import 'room_access_dialog.dart';
import 'member_management.dart';

class _PermissionEditor extends StatefulWidget {
  const _PermissionEditor({
    required this.initialValue,
    required this.label,
    required this.enabled,
    required this.onSave,
    super.key,
  });
  final int initialValue;
  final String label;
  final bool enabled;
  final ValueChanged<String> onSave;
  @override
  State<_PermissionEditor> createState() => _PermissionEditorState();
}

class _PermissionEditorState extends State<_PermissionEditor> {
  late String _value = '${widget.initialValue}';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(widget.label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              initialValue: _value,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Required power level',
              ),
              onChanged: (v) => _value = v,
              onFieldSubmitted: widget.onSave,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Save permission',
            onPressed: widget.enabled ? () => widget.onSave(_value) : null,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
    ],
  );
}

class SpaceAdministrationPanel extends StatefulWidget {
  const SpaceAdministrationPanel({
    required this.backend,
    required this.spaceId,
    super.key,
  });
  final ChatBackend backend;
  final String spaceId;
  @override
  State<SpaceAdministrationPanel> createState() =>
      _SpaceAdministrationPanelState();
}

class _SpaceAdministrationPanelState extends State<SpaceAdministrationPanel> {
  SpaceAdministration? _data;
  SpaceRoles _roles = const SpaceRoles();
  String? _target;
  bool _children = false;
  bool _busy = false;
  bool _dirty = false;
  String? _notice;
  Object? _revision;
  bool _loading = false;
  SpaceRoles? _reviewedRoles;

  @override
  void initState() {
    super.initState();
    _revision = widget.backend.spaceAdministrationRevision(widget.spaceId);
    widget.backend.addListener(_backendChanged);
    _load();
  }

  void _backendChanged() {
    final revision = widget.backend.spaceAdministrationRevision(widget.spaceId);
    if (_revision == revision) return;
    _revision = revision;
    if (_dirty || _busy) {
      setState(
        () => _notice =
            'Administration changed remotely. Reload before saving your draft.',
      );
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    widget.backend.removeListener(_backendChanged);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final data = await widget.backend.getSpaceAdministration(widget.spaceId);
      if (mounted) {
        setState(() {
          _data = data;
          _roles = data.roles;
          _reviewedRoles = data.roles;
          _target ??= widget.spaceId;
          _dirty = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Could not load administration. Check your connection and access, then retry.',
        );
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _editRole([SpaceRole? role]) async {
    final name = TextEditingController(text: role?.name ?? '');
    final power = TextEditingController(text: '${role?.powerLevel ?? 0}');
    final color = TextEditingController(
      text: role?.color?.toRadixString(16).padLeft(8, '0').substring(2) ?? '',
    );
    final result = await showDialog<SpaceRole>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final level = int.tryParse(power.text);
          final rgb = color.text.trim().replaceFirst('#', '');
          final valid =
              name.text.trim().isNotEmpty &&
              level != null &&
              level >= 0 &&
              level <= _data!.ownPower &&
              (rgb.isEmpty || RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(rgb));
          return AlertDialog(
            title: Text(role == null ? 'Create role' : 'Edit role'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'Role name'),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: power,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Power level (0–${_data!.ownPower})',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  TextField(
                    controller: color,
                    decoration: const InputDecoration(
                      labelText: 'Name colour (#RRGGBB, optional)',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: !valid
                    ? null
                    : () => Navigator.pop(
                        context,
                        SpaceRole(
                          id:
                              role?.id ??
                              'role-${DateTime.now().microsecondsSinceEpoch}',
                          name: name.text.trim(),
                          powerLevel: level,
                          color: rgb.isEmpty
                              ? null
                              : 0xff000000 | int.parse(rgb, radix: 16),
                        ),
                      ),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
    // Controllers belong to the dialog route until its reverse transition ends.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
    power.dispose();
    color.dispose();
    if (!mounted || result == null) return;
    setState(() {
      final next = [..._roles.roles];
      if (role == null) {
        next.add(result);
      } else {
        next[next.indexOf(role)] = result;
      }
      _roles = SpaceRoles(roles: next, members: _roles.members);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      await widget.backend.saveSpaceRoles(
        widget.spaceId,
        _roles,
        expected: _reviewedRoles,
      );
      _reviewedRoles = _roles;
      if (mounted) {
        setState(() {
          _dirty = false;
          _notice =
              'Role appearance saved. Apply role power below to update permissions in the chosen rooms.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice =
              'Roles could not be saved. Check permission/connection, or reload if another administrator changed them. No permission changes were requested.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<AdministrationRoom> get _targets => _data!.rooms
      .where(
        (room) =>
            room.id == _target || (_children && _target == widget.spaceId),
      )
      .toList();

  Future<void> _apply({AdministrationRule? rule, int? level}) async {
    final targets = _targets;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply permissions?'),
        content: Text(
          '${rule?.label ?? 'Role power levels'} will be applied to ${targets.length} room(s). '
          'Each room is independent; failures will be reported. Unrelated permissions stay unchanged. '
          'Existing manual member power is preserved when applying roles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final failures = <String>[];
    for (final room in targets) {
      try {
        if (rule == null) {
          await widget.backend.applySpaceRolePower(
            widget.spaceId,
            room.id,
            _roles,
          );
        } else {
          await widget.backend.setAdministrationRule(room.id, rule, level!);
        }
      } catch (_) {
        failures.add(room.name);
      }
    }
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = failures.isEmpty
          ? 'Applied to ${targets.length} room(s).'
          : 'Applied to ${targets.length - failures.length}/${targets.length}. Failed (check permission/access): ${failures.join(', ')}. Successful changes were not rolled back.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      return Column(
        children: [
          if (_notice != null) Text(_notice!),
          TextButton(
            onPressed: _load,
            child: const Text('Load administration'),
          ),
        ],
      );
    }
    final target =
        data.rooms.where((room) => room.id == _target).firstOrNull ??
        data.rooms.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_notice != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_notice!)),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Reload administration (discard draft)'),
        ),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => showRoomAccessDialog(
                  context,
                  widget.backend,
                  widget.spaceId,
                  isSpace: true,
                  children: data.rooms
                      .where((room) => room.id != widget.spaceId)
                      .toList(),
                ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Space access and shared timeline settings'),
        ),
        Text('Roles', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Topmost assigned colour wins; the highest assigned power level controls privileges. Role badges belong to server profiles, not direct messages.',
        ),
        for (final (index, role) in _roles.roles.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: role.color == null ? null : Color(role.color!),
              child: Text('${role.powerLevel}'),
            ),
            title: Text(role.name),
            onTap: _busy || !data.canEditRoles ? null : () => _editRole(role),
            trailing: Wrap(
              children: [
                IconButton(
                  tooltip: 'Move up',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: _busy || !data.canEditRoles || index == 0
                      ? null
                      : () => setState(() {
                          final next = [..._roles.roles]..removeAt(index);
                          next.insert(index - 1, role);
                          _roles = SpaceRoles(
                            roles: next,
                            members: _roles.members,
                          );
                          _dirty = true;
                        }),
                ),
                IconButton(
                  tooltip: 'Remove role',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy || !data.canEditRoles
                      ? null
                      : () => setState(() {
                          _roles = SpaceRoles(
                            roles: _roles.roles
                                .where((r) => r.id != role.id)
                                .toList(),
                            members: {
                              for (final entry in _roles.members.entries)
                                entry.key: entry.value
                                    .where((id) => id != role.id)
                                    .toSet(),
                            },
                          );
                          _dirty = true;
                        }),
                ),
              ],
            ),
          ),
        if (data.canEditRoles)
          TextButton.icon(
            onPressed: _busy ? null : () => _editRole(),
            icon: const Icon(Icons.add),
            label: const Text('Add role'),
          ),
        ExpansionTile(
          title: const Text('Member roles'),
          children: [
            for (final member in data.members.entries)
              ExpansionTile(
                title: Text(member.value),
                subtitle: Text(member.key),
                children: [
                  for (final role in _roles.roles)
                    CheckboxListTile(
                      title: Text(role.name),
                      value:
                          _roles.members[member.key]?.contains(role.id) == true,
                      onChanged: _busy || !data.canEditRoles
                          ? null
                          : (value) => setState(() {
                              final ids = {...?_roles.members[member.key]};
                              if (value == true) {
                                ids.add(role.id);
                              } else {
                                ids.remove(role.id);
                              }
                              _roles = SpaceRoles(
                                roles: _roles.roles,
                                members: {..._roles.members, member.key: ids},
                              );
                              _dirty = true;
                            }),
                    ),
                ],
              ),
          ],
        ),
        FilledButton(
          onPressed: _busy || !_dirty || !data.canEditRoles ? null : _save,
          child: const Text('Save roles'),
        ),
        const Divider(height: 32),
        Text('Rules', style: Theme.of(context).textTheme.titleLarge),
        const Text(
          'Matrix power levels apply per room. Threads share their room’s permissions. '
          'Creating a room itself is governed by the homeserver; linking it here is controlled below. '
          'Pack actions and channel actions sharing an event type share a permission. '
          'A timeout changes member power; there is no independent Matrix mute capability. '
          'Encrypted messages use the encrypted-event permission: the server cannot inspect their inner message type. '
          'Alias registration, media uploads and account creation also follow homeserver policy.',
        ),
        DropdownButtonFormField<String>(
          initialValue: target.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Room to administer'),
          items: [
            for (final room in data.rooms)
              DropdownMenuItem(
                value: room.id,
                child: Text(room.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _target = value;
                  _children = false;
                }),
        ),
        if (_target == widget.spaceId)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Also apply to child rooms'),
            subtitle: const Text(
              'Explicitly replaces this rule’s child-room overrides.',
            ),
            value: _children,
            onChanged: _busy
                ? null
                : (value) => setState(() => _children = value ?? false),
          ),
        if (_target != widget.spaceId)
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => showRoomAccessDialog(
                    context,
                    widget.backend,
                    target.id,
                    spaceId: widget.spaceId,
                  ),
            child: const Text('Channel access and timeline settings'),
          ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => showBannedMembers(context, widget.backend, target.id),
          icon: const Icon(Icons.person_off_outlined),
          label: const Text('Banned members'),
        ),
        OutlinedButton(
          onPressed: _busy || _dirty || !data.canEditRoles
              ? null
              : () => _apply(),
          child: const Text('Apply saved role power to selected rooms'),
        ),
        for (final rule in administrationRules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _PermissionEditor(
              key: ValueKey(
                '${target.id}/${rule.key}/${rule.level(target.powerLevels)}',
              ),
              initialValue: rule.level(target.powerLevels),
              label: rule.label,
              enabled: !_busy && !_dirty && target.canEdit,
              onSave: (value) {
                final level = int.tryParse(value);
                if (level == null || level < 0 || level > target.ownPower) {
                  setState(
                    () => _notice =
                        'Choose a level from 0 to ${target.ownPower} for this room.',
                  );
                  return;
                }
                _apply(rule: rule, level: level);
              },
            ),
          ),
      ],
    );
  }
}
