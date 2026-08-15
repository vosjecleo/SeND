import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

Future<void> showMemberProfile(
  BuildContext context,
  ChatBackend backend,
  RoomMemberSummary member,
) => showDialog<void>(
  context: context,
  builder: (context) => _ProfileDialog(backend: backend, member: member),
);

Future<void> showOwnProfile(BuildContext context, ChatBackend backend) {
  final userId = backend.userId ?? 'Unknown Matrix ID';
  return showDialog<void>(
    context: context,
    builder: (context) => _ProfileDialog(
      backend: backend,
      member: RoomMemberSummary(
        userId: userId,
        displayName: backend.profileDisplayName ?? _localpart(userId),
        avatarBytes: backend.profileAvatarBytes,
        presence: backend.preferences.sharePresence
            ? UserPresence.online
            : UserPresence.offline,
      ),
      own: true,
    ),
  );
}

String _localpart(String id) {
  final value = id.startsWith('@') ? id.substring(1) : id;
  return value.split(':').first;
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({
    required this.backend,
    required this.member,
    this.own = false,
  });

  final ChatBackend backend;
  final RoomMemberSummary member;
  final bool own;

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    return AlertDialog(
      title: const Text('Profile'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: SizedBox.square(
                dimension: 128,
                child: member.avatarBytes == null
                    ? ColoredBox(
                        color: const Color(0xff3a3c46),
                        child: Center(
                          child: Text(
                            member.displayName.characters.firstOrNull
                                    ?.toUpperCase() ??
                                '?',
                            style: const TextStyle(fontSize: 42),
                          ),
                        ),
                      )
                    : Image.memory(member.avatarBytes!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              member.displayName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SelectableText(member.userId),
            const SizedBox(height: 12),
            Text('Presence: ${member.presence.name}'),
            if (!widget.own)
              Text('Role: ${_role(member.powerLevel)} (${member.powerLevel})'),
            if (member.canChangePowerLevel) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: member.powerLevel,
                decoration: const InputDecoration(
                  labelText: 'Room power level',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('Member — 0')),
                  if (member.maxAssignablePowerLevel >= 50)
                    const DropdownMenuItem(
                      value: 50,
                      child: Text('Moderator — 50'),
                    ),
                  if (member.maxAssignablePowerLevel >= 100)
                    const DropdownMenuItem(
                      value: 100,
                      child: Text('Administrator — 100'),
                    ),
                  if (member.powerLevel != 0 &&
                      member.powerLevel != 50 &&
                      member.powerLevel != 100)
                    DropdownMenuItem(
                      value: member.powerLevel,
                      child: Text('Custom — ${member.powerLevel}'),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (value) async {
                        if (value == null) return;
                        setState(() => _saving = true);
                        try {
                          await widget.backend.setMemberPowerLevel(
                            member.userId,
                            value,
                          );
                          if (mounted) Navigator.of(this.context).pop();
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _role(int level) => level >= 100
      ? 'Administrator'
      : level >= 50
      ? 'Moderator'
      : 'Member';
}
