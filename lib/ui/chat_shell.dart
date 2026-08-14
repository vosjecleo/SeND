import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'security_center.dart';

class ChatShell extends StatefulWidget {
  const ChatShell({required this.backend, super.key});

  final ChatBackend backend;

  @override
  State<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends State<ChatShell> {
  final _message = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'message composer');
  bool _sending = false;
  ChatMessage? _replyingTo;
  ChatMessage? _editingMessage;

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _message.clear();
    try {
      await widget.backend.sendMessage(
        text,
        replyToMessageId: _replyingTo?.id,
        editMessageId: _editingMessage?.id,
      );
      if (mounted) {
        setState(() {
          _replyingTo = null;
          _editingMessage = null;
        });
      }
    } catch (_) {
      if (mounted) _message.text = text;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _replyTo(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  void _edit(ChatMessage message) {
    _message
      ..text = message.body
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: message.body.length,
      );
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
    });
    _composerFocus.requestFocus();
  }

  void _cancelComposerAction() {
    setState(() {
      _replyingTo = null;
      _editingMessage = null;
    });
    _composerFocus.requestFocus();
  }

  @override
  void dispose() {
    _message.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (widget.backend.encryptionSetup.needsAttention)
            _SecurityBanner(backend: widget.backend),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 68, child: _SpaceBar(backend: widget.backend)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 280,
                  child: _RoomPanel(backend: widget.backend),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: widget.backend.selectedRoom == null
                      ? const _EmptyConversation()
                      : _Conversation(
                          backend: widget.backend,
                          controller: _message,
                          composerFocus: _composerFocus,
                          sending: _sending,
                          replyingTo: _replyingTo,
                          editingMessage: _editingMessage,
                          onSend: _send,
                          onReply: _replyTo,
                          onEdit: _edit,
                          onCancelComposerAction: _cancelComposerAction,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff4b3c19),
    child: InkWell(
      onTap: () => showSecurityCenter(context, backend),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, size: 19),
            const SizedBox(width: 9),
            const Expanded(
              child: Text(
                'Encrypted history is not fully protected on this device.',
              ),
            ),
            TextButton(
              onPressed: () => showSecurityCenter(context, backend),
              child: const Text('Fix encryption'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SpaceBar extends StatelessWidget {
  const _SpaceBar({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff191a1e),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        children: [
          _SpaceButton(
            tooltip: 'Home',
            selected: backend.selectedSpaceId == null,
            onTap: () => backend.selectSpace(null),
            child: const Icon(Icons.home_filled, size: 21),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            child: Divider(height: 1),
          ),
          for (final space in backend.spaces)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: _SpaceButton(
                tooltip: space.name,
                selected: backend.selectedSpaceId == space.id,
                onTap: () => backend.selectSpace(space.id),
                child: space.avatarBytes == null
                    ? Text(
                        _initials(space.name),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : Image.memory(
                        space.avatarBytes!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    return words.take(2).map((word) => word[0].toUpperCase()).join();
  }
}

class _SpaceButton extends StatelessWidget {
  const _SpaceButton({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 48,
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : const Color(0xff2b2d34),
          borderRadius: BorderRadius.circular(selected ? 13 : 24),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(selected ? 13 : 24),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _RoomPanel extends StatelessWidget {
  const _RoomPanel({required this.backend});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff202126),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff35363d))),
            ),
            child: Text(
              backend.selectedSpaceId == null
                  ? 'Home'
                  : backend.spaces
                            .where(
                              (space) => space.id == backend.selectedSpaceId,
                            )
                            .map((space) => space.name)
                            .firstOrNull ??
                        'Space',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: backend.rooms.isEmpty
                ? const Center(child: Text('No joined rooms'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: backend.rooms.length,
                    itemBuilder: (context, index) {
                      final room = backend.rooms[index];
                      final selected = backend.selectedRoom?.id == room.id;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        leading: _RoomIcon(room: room, size: 30),
                        title: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          room.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: room.unreadCount > 0
                            ? Badge(label: Text('${room.unreadCount}'))
                            : null,
                        onTap: () => backend.selectRoom(room.id),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: Text(
              backend.userId ?? 'Matrix account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Encryption & recovery',
              icon: Icon(
                backend.encryptionSetup.status == EncryptionSetupStatus.ready
                    ? Icons.verified_user
                    : Icons.gpp_maybe,
                size: 19,
              ),
              onPressed: () => showSecurityCenter(context, backend),
            ),
          ),
          SizedBox(
            height: 34,
            child: TextButton.icon(
              onPressed: backend.logout,
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Log out'),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.room, required this.size});

  final RoomSummary room;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (room.usesChannelIcon) {
      return SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.tag, size: 18),
      );
    }
    final avatar = room.avatarBytes;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: const Color(0xff3a3c46),
      backgroundImage: avatar == null ? null : MemoryImage(avatar),
      child: avatar == null
          ? Text(
              room.name.trim().isEmpty
                  ? '?'
                  : room.name.trim().characters.first.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.4,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.backend,
    required this.controller,
    required this.composerFocus,
    required this.sending,
    required this.replyingTo,
    required this.editingMessage,
    required this.onSend,
    required this.onReply,
    required this.onEdit,
    required this.onCancelComposerAction,
  });

  final ChatBackend backend;
  final TextEditingController controller;
  final FocusNode composerFocus;
  final bool sending;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
  final VoidCallback onSend;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final VoidCallback onCancelComposerAction;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scrollController = ScrollController();
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _roomId = widget.backend.selectedRoom?.id;
    _scrollController.addListener(_loadHistoryNearTop);
    _focusComposerAfterBuild();
  }

  void _focusComposerAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.sending) widget.composerFocus.requestFocus();
    });
  }

  void _loadHistoryNearTop() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      widget.backend.loadMoreHistory();
    }
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomId = widget.backend.selectedRoom?.id;
    if (_roomId != roomId) {
      _roomId = roomId;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _focusComposerAfterBuild();
    } else if (oldWidget.sending && !widget.sending) {
      _focusComposerAfterBuild();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text(
          'This removes the message for everyone in the room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.backend.redactMessage(message.id);
  }

  Future<void> _pickReaction(ChatMessage message) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final emoji = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(origin.dx + 360, origin.dy + 120, 0, 0),
      items: const ['👍', '❤️', '😂', '🎉', '👀', '❓']
          .map(
            (emoji) => PopupMenuItem(
              value: emoji,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          )
          .toList(growable: false),
    );
    if (emoji != null) await widget.backend.toggleReaction(message.id, emoji);
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final room = backend.selectedRoom!;
    final messages = backend.messages;
    return Column(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            color: Color(0xff292a30),
            border: Border(bottom: BorderSide(color: Color(0xff35363d))),
          ),
          child: Row(
            children: [
              _RoomIcon(room: room, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  room.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        if (backend.error case final error?)
          MaterialBanner(
            content: Text(error),
            actions: [
              TextButton(
                onPressed: backend.clearError,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        Expanded(
          child: backend.timelineLoading
              ? const Center(child: CircularProgressIndicator())
              : backend.messages.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
                  itemCount:
                      messages.length +
                      (backend.historyLoading || backend.canLoadMoreHistory
                          ? 1
                          : 0),
                  itemBuilder: (context, index) {
                    if (index == messages.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Center(
                          child: backend.historyLoading
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton.icon(
                                  onPressed: backend.loadMoreHistory,
                                  icon: const Icon(Icons.history, size: 17),
                                  label: const Text('Load older messages'),
                                ),
                        ),
                      );
                    }
                    final message = messages[index];
                    final older = index + 1 < messages.length
                        ? messages[index + 1]
                        : null;
                    final startsGroup =
                        older == null ||
                        older.sender != message.sender ||
                        message.timestamp.difference(older.timestamp) >
                            const Duration(minutes: 7) ||
                        message.reply != null;
                    return _MessageRow(
                      message: message,
                      startsGroup: startsGroup,
                      onReply: () => widget.onReply(message),
                      onEdit: message.own && !message.redacted
                          ? () => widget.onEdit(message)
                          : null,
                      onDelete: message.canRedact
                          ? () => _deleteMessage(message)
                          : null,
                      onReact: message.redacted
                          ? null
                          : () => _pickReaction(message),
                      onToggleReaction: (key) =>
                          backend.toggleReaction(message.id, key),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        if (widget.replyingTo case final message?)
          _ComposerContext(
            label: 'Replying to ${message.sender}',
            body: message.body,
            onCancel: widget.onCancelComposerAction,
          )
        else if (widget.editingMessage case final message?)
          _ComposerContext(
            label: 'Editing message',
            body: message.body,
            onCancel: widget.onCancelComposerAction,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
          child: TextField(
            controller: widget.controller,
            focusNode: widget.composerFocus,
            autofocus: true,
            enabled: !widget.sending,
            onSubmitted: (_) => widget.onSend(),
            decoration: InputDecoration(
              hintText: 'Message #${room.name}',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                tooltip: 'Send',
                onPressed: widget.sending ? null : widget.onSend,
                icon: const Icon(Icons.send, size: 20),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.message,
    required this.startsGroup,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
    required this.onToggleReaction,
  });

  final ChatMessage message;
  final bool startsGroup;
  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;
  final ValueChanged<String> onToggleReaction;

  @override
  Widget build(BuildContext context) {
    final local = message.timestamp.toLocal();
    final now = DateTime.now();
    final clock = TimeOfDay.fromDateTime(local).format(context);
    final time =
        local.year == now.year &&
            local.month == now.month &&
            local.day == now.day
        ? clock
        : '${local.day}/${local.month}/${local.year} $clock';
    return Opacity(
      opacity: message.pending ? 0.55 : 1,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, startsGroup ? 10 : 2, 20, 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (startsGroup)
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xff3a3c46),
                backgroundImage: message.avatarBytes == null
                    ? null
                    : MemoryImage(message.avatarBytes!),
                child: message.avatarBytes == null
                    ? Text(
                        message.sender.trim().isEmpty
                            ? '?'
                            : message.sender.characters.first.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              )
            else
              const SizedBox(width: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message.reply case final reply?)
                    Container(
                      margin: const EdgeInsets.only(bottom: 5),
                      padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
                      decoration: const BoxDecoration(
                        color: Color(0xff292a30),
                        border: Border(
                          left: BorderSide(color: Color(0xff747fdb), width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                  if (startsGroup)
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            message.sender,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: const Color(0xff989aa5)),
                        ),
                        const Spacer(),
                        _MessageActions(
                          onReply: onReply,
                          onEdit: onEdit,
                          onDelete: onDelete,
                          onReact: onReact,
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: SelectableText(
                      message.body,
                      style: TextStyle(
                        height: 1.28,
                        fontStyle: message.redacted
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: message.redacted
                            ? const Color(0xff989aa5)
                            : null,
                      ),
                    ),
                  ),
                  if (message.edited)
                    const Text(
                      '(edited)',
                      style: TextStyle(fontSize: 11, color: Color(0xff989aa5)),
                    ),
                  if (message.failed)
                    const Text(
                      'Failed to send',
                      style: TextStyle(fontSize: 11, color: Colors.redAccent),
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
                              label: Text('${reaction.key} ${reaction.count}'),
                              onPressed: () => onToggleReaction(reaction.key),
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
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onReact,
  });

  final VoidCallback onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onReact;

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
        onSelected: (action) => switch (action) {
          'react' => onReact?.call(),
          'edit' => onEdit?.call(),
          'delete' => onDelete?.call(),
          _ => null,
        },
        itemBuilder: (context) => [
          if (onReact != null)
            const PopupMenuItem(value: 'react', child: Text('Add reaction')),
          if (onEdit != null)
            const PopupMenuItem(value: 'edit', child: Text('Edit message')),
          if (onDelete != null)
            const PopupMenuItem(value: 'delete', child: Text('Delete message')),
        ],
      ),
    ],
  );
}

class _ComposerContext extends StatelessWidget {
  const _ComposerContext({
    required this.label,
    required this.body,
    required this.onCancel,
  });

  final String label;
  final String body;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xff202126),
    padding: const EdgeInsets.fromLTRB(16, 6, 8, 4),
    child: Row(
      children: [
        const Icon(Icons.subdirectory_arrow_right, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                body.replaceAll('\n', ' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xff989aa5)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Cancel',
          visualDensity: VisualDensity.compact,
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 16),
        ),
      ],
    ),
  );
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.forum_outlined, size: 46),
        SizedBox(height: 12),
        Text('Choose a room to start chatting'),
      ],
    ),
  );
}
