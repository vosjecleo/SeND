part of 'chat_shell.dart';

class _MessageRow extends StatefulWidget {
  const _MessageRow({
    required this.message,
    required this.startsGroup,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
    required this.onToggleReaction,
    required this.backend,
  });

  final ChatMessage message;
  final bool startsGroup;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final ValueChanged<String> onToggleReaction;
  final ChatBackend backend;

  @override
  State<_MessageRow> createState() => _MessageRowState();
}

class _MessageRowState extends State<_MessageRow> {
  Timer? _dismissActionsTimer;
  final _actionsOverlay = OverlayPortalController();
  bool _hovered = false;
  bool _actionsHovered = false;
  bool _actionsMenuOpen = false;
  Offset _actionsPosition = Offset.zero;

  ChatMessage get message => widget.message;

  void _showSenderProfile() {
    final userId = message.senderId;
    if (userId == null) return;
    final members = widget.backend.selectedRoomMembers;
    final member = members
        .where((candidate) => candidate.userId == userId)
        .firstOrNull;
    showMemberProfile(
      context,
      widget.backend,
      member ??
          RoomMemberSummary(
            userId: userId,
            displayName: message.sender,
            avatarBytes: message.avatarBytes,
            presence: UserPresence.offline,
          ),
    );
  }

  void _enter(PointerEnterEvent _) {
    setState(() => _hovered = true);
  }

  void _exit(PointerExitEvent _) {
    setState(() => _hovered = false);
  }

  void _showActions(Offset globalPosition) {
    _dismissActionsTimer?.cancel();
    final viewport = MediaQuery.sizeOf(context);
    setState(() {
      _actionsHovered = false;
      _actionsPosition = Offset(
        globalPosition.dx.clamp(0, viewport.width - 96),
        globalPosition.dy.clamp(0, viewport.height - 48),
      );
    });
    _actionsOverlay.show();
    _scheduleActionsDismissal();
  }

  void _actionsEnter(PointerEnterEvent _) {
    _dismissActionsTimer?.cancel();
    _actionsHovered = true;
  }

  void _actionsExit(PointerExitEvent _) {
    _actionsHovered = false;
    _scheduleActionsDismissal();
  }

  void _scheduleActionsDismissal() {
    _dismissActionsTimer?.cancel();
    if (_actionsMenuOpen) return;
    _dismissActionsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_actionsHovered && !_actionsMenuOpen) {
        _actionsOverlay.hide();
      }
    });
  }

  void _actionsMenuOpened() {
    _dismissActionsTimer?.cancel();
    _actionsMenuOpen = true;
  }

  void _actionsMenuClosed() {
    _actionsMenuOpen = false;
    if (!_actionsHovered) _scheduleActionsDismissal();
  }

  void _reply() {
    _actionsOverlay.hide();
    widget.onReply();
  }

  @override
  void dispose() {
    _dismissActionsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        widget.backend.preferences.density == InterfaceDensity.compact;
    final local = message.timestamp.toLocal();
    final now = DateTime.now();
    final clock = TimeOfDay.fromDateTime(local).format(context);
    final time =
        local.year == now.year &&
            local.month == now.month &&
            local.day == now.day
        ? clock
        : '${local.day}/${local.month}/${local.year} $clock';
    if (message.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 7),
        child: Text(
          message.body,
          style: const TextStyle(
            color: Color(0xff989aa5),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }
    return OverlayPortal(
      controller: _actionsOverlay,
      overlayChildBuilder: (context) => Positioned(
        left: _actionsPosition.dx,
        top: _actionsPosition.dy,
        child: MouseRegion(
          onEnter: _actionsEnter,
          onExit: _actionsExit,
          child: Material(
            type: MaterialType.transparency,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xff202126),
                border: Border.all(color: const Color(0xff41434c)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _MessageActions(
                onReply: _reply,
                onEdit: widget.onEdit,
                onDelete: widget.onDelete,
                onReact: widget.onReact,
                onRetry: widget.onRetry,
                onCancel: widget.onCancel,
                onMenuOpened: _actionsMenuOpened,
                onMenuClosed: _actionsMenuClosed,
              ),
            ),
          ),
        ),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            _showActions(event.position);
          }
        },
        child: MouseRegion(
          onEnter: _enter,
          onExit: _exit,
          child: AnimatedContainer(
            duration: widget.backend.preferences.reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 110),
            color: _hovered ? const Color(0xff292a30) : Colors.transparent,
            child: Opacity(
              opacity: message.pending ? 0.55 : 1,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      widget.startsGroup
                          ? (compact ? 6 : 10)
                          : (compact ? 1 : 3),
                      20,
                      1,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(width: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.startsGroup)
                                Row(
                                  children: [
                                    Flexible(
                                      child: InkWell(
                                        onTap: _showSenderProfile,
                                        child: Text(
                                          message.sender,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            height: 1.05,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      time,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: const Color(0xff989aa5),
                                          ),
                                    ),
                                  ],
                                ),
                              if (message.reply case final reply?)
                                Container(
                                  margin: const EdgeInsets.only(
                                    top: 3,
                                    bottom: 2,
                                  ),
                                  padding: const EdgeInsets.fromLTRB(
                                    9,
                                    5,
                                    9,
                                    6,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xff292a30),
                                    border: Border(
                                      left: BorderSide(
                                        color: Color(0xff747fdb),
                                        width: 3,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        reply.sender,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xffb8bfff),
                                        ),
                                      ),
                                      Text(
                                        reply.body.replaceAll('\n', ' '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              if (message.body.isNotEmpty)
                                message.formattedBody != null
                                    ? MatrixHtmlText(
                                        html: message.formattedBody!,
                                        fallback: message.body,
                                      )
                                    : MatrixPlainText(
                                        text: message.body,
                                        style: TextStyle(
                                          height: 1.16,
                                          fontStyle: message.redacted
                                              ? FontStyle.italic
                                              : FontStyle.normal,
                                          color: message.redacted
                                              ? const Color(0xff989aa5)
                                              : null,
                                        ),
                                      ),
                              if (message.attachment case final attachment?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _AttachmentView(
                                    backend: widget.backend,
                                    messageId: message.id,
                                    attachment: attachment,
                                  ),
                                ),
                              if (message.linkPreview case final preview?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: _LinkPreviewCard(preview: preview),
                                ),
                              if (message.edited)
                                const Text(
                                  '(edited)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xff989aa5),
                                  ),
                                ),
                              if (message.own &&
                                  !message.failed &&
                                  !message.pending)
                                Tooltip(
                                  message: message.readBy.isEmpty
                                      ? 'Sent to homeserver'
                                      : 'Read by ${message.readBy.map((reader) => reader.displayName).join(', ')}',
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      message.readBy.isEmpty
                                          ? Icons.check
                                          : Icons.done_all,
                                      size: 14,
                                      color: message.readBy.isEmpty
                                          ? const Color(0xff989aa5)
                                          : const Color(0xff8fa2ff),
                                    ),
                                  ),
                                ),
                              if (message.queued)
                                const Text(
                                  'Queued — retrying after reconnect',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffffc857),
                                  ),
                                )
                              else if (message.failed)
                                Row(
                                  children: [
                                    const Text(
                                      'Failed to send',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: widget.onRetry,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              if (message.transferStatus case final status?)
                                Text(
                                  status,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xffb8bfff),
                                  ),
                                ),
                              if (message.reactions.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      for (final reaction in message.reactions)
                                        ActionChip(
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: reaction.reactedByMe
                                              ? const Color(0xff424a78)
                                              : const Color(0xff303139),
                                          label: Text(
                                            '${reaction.key} ${reaction.count}',
                                          ),
                                          onPressed: () => widget
                                              .onToggleReaction(reaction.key),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.startsGroup)
                    Positioned(
                      left: 20,
                      top: 10,
                      child: GestureDetector(
                        onTap: _showSenderProfile,
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: const Color(0xff3a3c46),
                          backgroundImage: message.avatarBytes == null
                              ? null
                              : MemoryImage(message.avatarBytes!),
                          child: message.avatarBytes == null
                              ? Text(
                                  message.sender.trim().isEmpty
                                      ? '?'
                                      : message.sender.characters.first
                                            .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 9),
          child: Text(
            'NEW',
            style: TextStyle(
              color: Color(0xffff8b91),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xffff6f77), thickness: 1)),
      ],
    ),
  );
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onRetry,
    required this.onCancel,
    required this.onMenuOpened,
    required this.onMenuClosed,
  });

  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback onMenuOpened;
  final VoidCallback onMenuClosed;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Reply',
        onPressed: onReply,
        icon: const Icon(Icons.reply, size: 16),
      ),
      PopupMenuButton<String>(
        tooltip: 'Message actions',
        iconSize: 17,
        onOpened: onMenuOpened,
        onCanceled: onMenuClosed,
        onSelected: (action) {
          switch (action) {
            case 'react':
              onReact?.call();
            case 'edit':
              onEdit?.call();
            case 'delete':
              onDelete?.call();
            case 'retry':
              onRetry?.call();
            case 'cancel':
              onCancel?.call();
          }
          onMenuClosed();
        },
        itemBuilder: (context) => [
          if (onReact != null)
            const PopupMenuItem(value: 'react', child: Text('Add reaction')),
          if (onEdit != null)
            const PopupMenuItem(value: 'edit', child: Text('Edit message')),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('Delete message')),
          if (onRetry != null)
            const PopupMenuItem(value: 'retry', child: Text('Retry send')),
          if (onCancel != null)
            const PopupMenuItem(
              value: 'cancel',
              child: Text('Remove failed send'),
            ),
        ],
      ),
    ],
  );
}
