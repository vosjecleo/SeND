import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';
import 'profile_card.dart';
import 'profile_editor_dialog.dart';

Future<void> showMemberProfile(
  BuildContext context,
  ChatBackend backend,
  RoomMemberSummary member, {
  Offset? anchor,
}) => _showProfilePopover(
  context,
  backend,
  member,
  own: member.userId == backend.userId,
  anchor: anchor == null
      ? _profileAnchorRect(context)
      : Rect.fromCenter(center: anchor, width: 1, height: 1),
  placement: _ProfilePopoverPlacement.beside,
);

Future<void> showOwnProfile(BuildContext context, ChatBackend backend) {
  final userId = backend.userId ?? 'Unknown Matrix ID';
  return _showProfilePopover(
    context,
    backend,
    RoomMemberSummary(
      userId: userId,
      displayName: backend.profileDisplayName ?? _localpart(userId),
      avatarBytes: backend.profileAvatarBytes,
      presence: backend.profilePresence,
    ),
    own: true,
    anchor: _profileAnchorRect(context),
    placement: _ProfilePopoverPlacement.above,
  );
}

Future<void> showFullMemberProfile(
  BuildContext context,
  ChatBackend backend,
  RoomMemberSummary member,
) => showDialog<void>(
  context: context,
  builder: (context) => _ProfileDialog(
    backend: backend,
    member: member,
    own: member.userId == backend.userId,
  ),
);

Future<void> showFullOwnProfile(BuildContext context, ChatBackend backend) {
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

enum _ProfilePopoverPlacement { above, beside }

Rect _profileAnchorRect(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.attached) {
    return Rect.zero;
  }
  return renderObject.localToGlobal(Offset.zero) & renderObject.size;
}

Future<void> _showProfilePopover(
  BuildContext context,
  ChatBackend backend,
  RoomMemberSummary member, {
  required bool own,
  required Rect anchor,
  required _ProfilePopoverPlacement placement,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close profile',
  barrierColor: Colors.black38,
  transitionDuration: const Duration(milliseconds: 120),
  pageBuilder: (dialogContext, _, _) => _ProfilePopoverPositioner(
    sourceContext: context,
    backend: backend,
    member: member,
    own: own,
    anchor: anchor,
    placement: placement,
  ),
  transitionBuilder: (context, animation, _, child) => FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: Tween(begin: 0.97, end: 1.0).animate(animation),
      child: child,
    ),
  ),
);

String _localpart(String id) {
  final value = id.startsWith('@') ? id.substring(1) : id;
  return value.split(':').first;
}

class _ProfilePopoverPositioner extends StatelessWidget {
  const _ProfilePopoverPositioner({
    required this.sourceContext,
    required this.backend,
    required this.member,
    required this.own,
    required this.anchor,
    required this.placement,
  });

  final BuildContext sourceContext;
  final ChatBackend backend;
  final RoomMemberSummary member;
  final bool own;
  final Rect anchor;
  final _ProfilePopoverPlacement placement;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = min(340.0, constraints.maxWidth - 24);
      final availableHeight = constraints.maxHeight - 24;
      late final double left;
      if (placement == _ProfilePopoverPlacement.above) {
        left = anchor.left
            .clamp(12.0, constraints.maxWidth - width - 12.0)
            .toDouble();
        final bottom = (constraints.maxHeight - anchor.top + 8).clamp(
          12.0,
          max(12.0, constraints.maxHeight - 232),
        );
        final maxHeight = max(0.0, constraints.maxHeight - bottom - 12);
        return Stack(
          children: [
            Positioned(
              left: left,
              bottom: bottom.toDouble(),
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _ProfilePopover(
                  sourceContext: sourceContext,
                  backend: backend,
                  member: member,
                  own: own,
                ),
              ),
            ),
          ],
        );
      }
      final rightCandidate = anchor.right + 12;
      left = rightCandidate + width <= constraints.maxWidth - 12
          ? rightCandidate
          : max(12.0, anchor.left - width - 12.0);
      final top = (anchor.center.dy - 96)
          .clamp(
            12.0,
            max(
              12.0,
              constraints.maxHeight - min(520.0, availableHeight) - 12.0,
            ),
          )
          .toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight - top - 12,
              ),
              child: _ProfilePopover(
                sourceContext: sourceContext,
                backend: backend,
                member: member,
                own: own,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _ProfilePopover extends StatefulWidget {
  const _ProfilePopover({
    required this.sourceContext,
    required this.backend,
    required this.member,
    required this.own,
  });

  final BuildContext sourceContext;
  final ChatBackend backend;
  final RoomMemberSummary member;
  final bool own;

  @override
  State<_ProfilePopover> createState() => _ProfilePopoverState();
}

class _ProfilePopoverState extends State<_ProfilePopover> {
  late Future<UserProfileSummary> _profile = widget.backend.getUserProfile(
    widget.member.userId,
  );
  late int _profileRevision = widget.backend.profileRevision;

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_backendChanged);
    unawaited(_refreshInBackground());
  }

  Future<void> _refreshInBackground() async {
    try {
      final profile = await widget.backend.getUserProfile(
        widget.member.userId,
        refresh: true,
      );
      if (mounted) setState(() => _profile = Future.value(profile));
    } catch (_) {
      // Keep showing cached data if the homeserver cannot be reached.
    }
  }

  void _backendChanged() {
    final revision = widget.backend.profileRevision;
    if (!mounted || revision == _profileRevision) return;
    _profileRevision = revision;
    setState(() {
      _profile = widget.backend.getUserProfile(widget.member.userId);
    });
  }

  @override
  void dispose() {
    widget.backend.removeListener(_backendChanged);
    super.dispose();
  }

  Future<void> _edit(UserProfileSummary profile) async {
    final changed = await showProfileEditor(context, widget.backend, profile);
    if (changed && mounted) {
      setState(
        () => _profile = widget.backend.getUserProfile(widget.member.userId),
      );
    }
  }

  void _openFullProfile() {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.sourceContext.mounted) return;
      if (widget.own) {
        showFullOwnProfile(widget.sourceContext, widget.backend);
      } else {
        showFullMemberProfile(
          widget.sourceContext,
          widget.backend,
          widget.member,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserProfileSummary>(
    future: _profile,
    builder: (context, snapshot) {
      final profile = snapshot.data;
      if (profile == null) {
        return const _ProfileLoadingCard(compact: true);
      }
      return Material(
        key: const Key('compact-profile-popup'),
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: DeltiecordProfileCard(
                scrollable: true,
                profile: profile,
                onEdit: widget.own ? () => _edit(profile) : null,
                onMessage: widget.own
                    ? null
                    : () async {
                        Navigator.of(context).pop();
                        await widget.backend.startDirectChat(
                          widget.member.userId,
                        );
                      },
              ),
            ),
            TextButton(
              onPressed: _openFullProfile,
              child: const Text('View full profile'),
            ),
          ],
        ),
      );
    },
  );
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
  late Future<UserProfileSummary> _profile = widget.backend.getUserProfile(
    widget.member.userId,
  );
  late int _profileRevision = widget.backend.profileRevision;

  Future<UserProfileSummary> _loadProfile() =>
      widget.backend.getUserProfile(widget.member.userId, refresh: true);

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_backendChanged);
    unawaited(_refreshInBackground());
  }

  Future<void> _refreshInBackground() async {
    try {
      final profile = await _loadProfile();
      if (mounted) setState(() => _profile = Future.value(profile));
    } catch (_) {
      // Keep showing the cache while an offline refresh fails.
    }
  }

  void _backendChanged() {
    final revision = widget.backend.profileRevision;
    if (!mounted || revision == _profileRevision) return;
    _profileRevision = revision;
    setState(() {
      _profile = widget.backend.getUserProfile(widget.member.userId);
    });
  }

  @override
  void dispose() {
    widget.backend.removeListener(_backendChanged);
    super.dispose();
  }

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
        minWidth: 0,
        maxWidth: 700,
        maxHeight: 860,
      ),
      child: FutureBuilder<UserProfileSummary>(
        future: _profile,
        builder: (context, snapshot) {
          final profile = snapshot.data;
          if (profile == null) {
            return const _ProfileLoadingCard(compact: false);
          }
          return DeltiecordProfileCard(
            scrollable: true,
            profile: profile,
            onEdit: widget.own ? () => _edit(profile) : null,
            onClose: Navigator.of(context).pop,
            onMessage: widget.own
                ? null
                : () async {
                    Navigator.of(context).pop();
                    await widget.backend.startDirectChat(widget.member.userId);
                  },
            onBlock: widget.own ? null : _toggleBlock,
            blocked: widget.backend.blockedUserIds.contains(
              widget.member.userId,
            ),
            footer: !widget.own || widget.member.canChangePowerLevel
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _RoomRolePanel(
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
                  )
                : null,
          );
        },
      ),
    ),
  );
}

class _ProfileLoadingCard extends StatelessWidget {
  const _ProfileLoadingCard({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('profile-loading-state'),
    color: context.deltiecord.surface,
    shape: RoundedRectangleBorder(borderRadius: DeltiecordCorners.borderRadius),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: compact ? 340 : 620,
      height: compact ? 240 : 420,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('Loading profile…'),
          ],
        ),
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
