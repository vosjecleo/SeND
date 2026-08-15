import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late final Future<UserProfileSummary> _profile = widget.backend
      .getUserProfile(widget.member.userId);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Profile'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<UserProfileSummary>(
          future: _profile,
          builder: (context, snapshot) {
            final member = widget.member;
            final profile = snapshot.data;
            final avatar = profile?.avatarBytes ?? member.avatarBytes;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (profile?.bannerBytes case final banner?)
                    SizedBox(
                      width: double.infinity,
                      height: 112,
                      child: Image.memory(banner, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 8),
                  ClipOval(
                    child: SizedBox.square(
                      dimension: 128,
                      child: avatar == null
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
                          : Image.memory(avatar, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    profile?.displayName ?? member.displayName,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SelectableText(member.userId),
                  const SizedBox(height: 10),
                  Text(
                    'Presence: ${(profile?.presence ?? member.presence).name}',
                  ),
                  if (profile?.pronouns case final pronouns?)
                    Text('Pronouns: $pronouns'),
                  if (profile?.timezone case final timezone?)
                    Text('Timezone: $timezone'),
                  if (profile?.bio case final bio?) ...[
                    const Divider(height: 22),
                    Align(alignment: Alignment.centerLeft, child: Text(bio)),
                  ],
                  if (!widget.own)
                    Text(
                      'Role: ${_role(member.powerLevel)} (${member.powerLevel})',
                    ),
                  if (member.canChangePowerLevel) ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: member.powerLevel,
                      decoration: const InputDecoration(
                        labelText: 'Room power level',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Member — 0'),
                        ),
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
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Copy Matrix ID',
          onPressed: () =>
              Clipboard.setData(ClipboardData(text: widget.member.userId)),
          icon: const Icon(Icons.copy, size: 18),
        ),
        if (!widget.own) ...[
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await widget.backend.startDirectChat(widget.member.userId);
            },
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
          ),
          TextButton.icon(
            onPressed: () async {
              final blocked = widget.backend.blockedUserIds.contains(
                widget.member.userId,
              );
              await widget.backend.setUserBlocked(
                widget.member.userId,
                !blocked,
              );
              if (mounted) Navigator.of(this.context).pop();
            },
            icon: const Icon(Icons.block, size: 18),
            label: Text(
              widget.backend.blockedUserIds.contains(widget.member.userId)
                  ? 'Unblock'
                  : 'Block',
            ),
          ),
        ],
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
