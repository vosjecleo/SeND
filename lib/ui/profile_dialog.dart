import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';

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
        presence: backend.profilePresence,
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
  late Future<UserProfileSummary> _profile = _loadProfile();

  Future<UserProfileSummary> _loadProfile() =>
      widget.backend.getUserProfile(widget.member.userId);

  Future<void> _edit(UserProfileSummary profile) async {
    final changed = await showProfileEditor(context, widget.backend, profile);
    if (changed && mounted) setState(() => _profile = _loadProfile());
  }

  Future<void> _toggleBlock() async {
    final blocked = widget.backend.blockedUserIds.contains(
      widget.member.userId,
    );
    await widget.backend.setUserBlocked(widget.member.userId, !blocked);
    if (mounted) setState(() => _profile = _loadProfile());
  }

  @override
  Widget build(BuildContext context) => Dialog(
    key: const Key('profile-side-panel'),
    alignment: widget.own ? Alignment.center : Alignment.centerRight,
    insetPadding: const EdgeInsets.all(12),
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 620,
        maxWidth: 700,
        maxHeight: 860,
      ),
      child: FutureBuilder<UserProfileSummary>(
        future: _profile,
        builder: (context, snapshot) {
          final profile =
              snapshot.data ??
              UserProfileSummary(
                userId: widget.member.userId,
                displayName: widget.member.displayName,
                avatarBytes: widget.member.avatarBytes,
                presence: widget.member.presence,
              );
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DeltiecordProfileCard(
                  profile: profile,
                  onEdit: widget.own ? () => _edit(profile) : null,
                  onClose: Navigator.of(context).pop,
                  onMessage: widget.own
                      ? null
                      : () async {
                          Navigator.of(context).pop();
                          await widget.backend.startDirectChat(
                            widget.member.userId,
                          );
                        },
                  onBlock: widget.own ? null : _toggleBlock,
                  blocked: widget.backend.blockedUserIds.contains(
                    widget.member.userId,
                  ),
                ),
                if (!widget.own || widget.member.canChangePowerLevel) ...[
                  const SizedBox(height: 14),
                  _RoomRolePanel(
                    member: widget.member,
                    saving: _saving,
                    onChanged: widget.member.canChangePowerLevel
                        ? (value) async {
                            setState(() => _saving = true);
                            try {
                              await widget.backend.setMemberPowerLevel(
                                widget.member.userId,
                                value,
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _saving = false);
                              }
                            }
                          }
                        : null,
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
  );
}

class _RoomRolePanel extends StatelessWidget {
  const _RoomRolePanel({
    required this.member,
    required this.saving,
    required this.onChanged,
  });

  final RoomMemberSummary member;
  final bool saving;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Room role: ${_role(member.powerLevel)} (${member.powerLevel})',
            ),
          ),
          if (onChanged != null)
            SizedBox(
              width: 230,
              child: DropdownButtonFormField<int>(
                initialValue: member.powerLevel,
                decoration: const InputDecoration(labelText: 'Power level'),
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
                onChanged: saving
                    ? null
                    : (value) {
                        if (value != null) onChanged!(value);
                      },
              ),
            ),
        ],
      ),
    ),
  );

  String _role(int level) => level >= 100
      ? 'Administrator'
      : level >= 50
      ? 'Moderator'
      : 'Member';
}
