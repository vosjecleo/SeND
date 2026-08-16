part of 'chat_shell.dart';

class _SidePanelRegion extends StatefulWidget {
  const _SidePanelRegion({
    required this.visible,
    required this.width,
    required this.onToggle,
    required this.onResize,
    required this.child,
  });

  final bool visible;
  final double width;
  final VoidCallback onToggle;
  final ValueChanged<double> onResize;
  final Widget child;

  @override
  State<_SidePanelRegion> createState() => _SidePanelRegionState();
}

class _SidePanelRegionState extends State<_SidePanelRegion> {
  bool _resizing = false;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.visible)
        MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: GestureDetector(
            key: const Key('side-panel-resize-handle'),
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _resizing = true),
            onHorizontalDragUpdate: (details) =>
                widget.onResize(details.delta.dx),
            onHorizontalDragEnd: (_) => setState(() => _resizing = false),
            onHorizontalDragCancel: () => setState(() => _resizing = false),
            child: SizedBox(
              width: 5,
              child: Center(
                child: VerticalDivider(
                  width: 1,
                  color: context.deltiecord.divider,
                ),
              ),
            ),
          ),
        ),
      SizedBox(
        width: 24,
        child: Align(
          alignment: Alignment.center,
          child: Material(
            color: context.deltiecord.elevated,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: context.deltiecord.divider),
              borderRadius: BorderRadius.circular(3),
            ),
            child: InkWell(
              key: const Key('side-panel-toggle'),
              onTap: widget.onToggle,
              child: SizedBox(
                width: 20,
                height: 42,
                child: Icon(
                  widget.visible ? Icons.chevron_right : Icons.chevron_left,
                  size: 18,
                ),
              ),
            ),
          ),
        ),
      ),
      TweenAnimationBuilder<double>(
        key: const Key('side-panel-width'),
        tween: Tween(end: widget.visible ? widget.width : 0),
        duration: _resizing ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: widget.child,
        builder: (context, width, panel) => ClipRect(
          child: SizedBox(
            width: width,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: widget.width,
              maxWidth: widget.width,
              child: Transform.translate(
                offset: Offset(widget.width - width, 0),
                child: panel,
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class _MemberSidebar extends StatelessWidget {
  const _MemberSidebar({required this.backend, required this.members});

  final ChatBackend backend;
  final List<RoomMemberSummary> members;

  @override
  Widget build(BuildContext context) {
    final administrators = members
        .where((member) => member.powerLevel >= 50)
        .toList(growable: false);
    final regularMembers = members
        .where((member) => member.powerLevel < 50)
        .toList(growable: false);
    return DecoratedBox(
      key: const Key('member-side-panel'),
      decoration: BoxDecoration(
        color: context.deltiecord.panel,
        border: Border(left: BorderSide(color: context.deltiecord.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.deltiecord.surface,
              border: Border(
                bottom: BorderSide(color: context.deltiecord.divider),
              ),
            ),
            child: Text(
              'Members — ${members.length}',
              style: const TextStyle(
                fontSize: DeltiecordTypeScale.bigUi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (administrators.isNotEmpty) ...[
                  _MemberSectionLabel(
                    label: 'MODERATORS — ${administrators.length}',
                  ),
                  for (final member in administrators)
                    _MemberSidebarTile(backend: backend, member: member),
                ],
                if (regularMembers.isNotEmpty) ...[
                  _MemberSectionLabel(
                    label: 'MEMBERS — ${regularMembers.length}',
                  ),
                  for (final member in regularMembers)
                    _MemberSidebarTile(backend: backend, member: member),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberSectionLabel extends StatelessWidget {
  const _MemberSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 9, 12, 4),
    child: Text(
      label,
      style: TextStyle(
        color: context.deltiecord.muted,
        fontSize: DeltiecordTypeScale.normal,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MemberSidebarTile extends StatelessWidget {
  const _MemberSidebarTile({required this.backend, required this.member});

  final ChatBackend backend;
  final RoomMemberSummary member;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: context.deltiecord.elevated,
            backgroundImage: member.avatarBytes == null
                ? null
                : MemoryImage(member.avatarBytes!),
            child: member.avatarBytes == null
                ? Text(
                    member.displayName.trim().isEmpty
                        ? '?'
                        : member.displayName.characters.first.toUpperCase(),
                  )
                : null,
          ),
          Positioned(
            left: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (member.presence) {
                  UserPresence.online => const Color(0xff43b581),
                  UserPresence.away => const Color(0xffffc857),
                  UserPresence.offline => const Color(0xff747680),
                },
                border: Border.all(color: context.deltiecord.panel, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        member.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: DeltiecordTypeScale.bigChat,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: member.powerLevel >= 50
          ? Text(
              member.powerLevel >= 100 ? 'Administrator' : 'Moderator',
              style: TextStyle(color: context.deltiecord.muted),
            )
          : null,
      onTap: () => showMemberProfile(context, backend, member),
    ),
  );
}
