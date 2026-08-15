part of 'chat_shell.dart';

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
    required this.onAttach,
    required this.onGif,
    required this.onPasteImage,
    required this.onDropAttachments,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
    required this.composerKey,
    super.key,
  });

  final ChatBackend backend;
  final QuillController controller;
  final FocusNode composerFocus;
  final bool sending;
  final ChatMessage? replyingTo;
  final ChatMessage? editingMessage;
  final VoidCallback onSend;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final VoidCallback onCancelComposerAction;
  final VoidCallback onAttach;
  final VoidCallback onGif;
  final Future<bool> Function() onPasteImage;
  final ValueChanged<List<AttachmentDraft>> onDropAttachments;
  final List<AttachmentDraft> pendingAttachments;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onToggleAttachmentSpoiler;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;
  final GlobalKey<_RichComposerState> composerKey;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  String? _roomId;
  bool _loadingAnchoredHistory = false;
  bool _draggingFiles = false;

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
      _loadOlderAnchored();
    }
  }

  Future<void> _loadOlderAnchored() async {
    if (_loadingAnchoredHistory || !_scrollController.hasClients) return;
    _loadingAnchoredHistory = true;
    final position = _scrollController.position;
    final oldPixels = position.pixels;
    final oldExtent = position.maxScrollExtent;
    final preferences = widget.backend.preferences;
    final atCap =
        widget.backend.messages.length >=
        min(120, preferences.timelineChunkSize * preferences.timelineChunkCap);
    await widget.backend.loadMoreHistory();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (atCap) {
        final extentDelta =
            _scrollController.position.maxScrollExtent - oldExtent;
        _scrollController.jumpTo(
          (oldPixels + extentDelta).clamp(
            0,
            _scrollController.position.maxScrollExtent,
          ),
        );
      }
      _loadingAnchoredHistory = false;
    });
  }

  void _jumpToFirstUnread() {
    final eventId = widget.backend.firstUnreadMessageId;
    if (eventId == null || !_scrollController.hasClients) return;
    final index = widget.backend.messages.indexWhere(
      (message) => message.id == eventId,
    );
    if (index < 0) return;
    final estimated = (index * 64.0).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(estimated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _messageKeys[eventId]?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 180),
          alignment: 0.5,
        );
      }
    });
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

  Future<void> showSearch() async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _RoomSearchDialog(backend: widget.backend, onSelected: _jumpToEvent),
    );
  }

  void _showPins() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Pinned messages'),
      content: SizedBox(
        width: 460,
        child: widget.backend.pinnedMessages.isEmpty
            ? const Text('No loaded pinned messages')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final message in widget.backend.pinnedMessages)
                    ListTile(
                      dense: true,
                      title: Text(message.sender),
                      subtitle: Text(message.body),
                      onTap: () {
                        Navigator.of(context).pop();
                        _jumpToEvent(message.id);
                      },
                    ),
                ],
              ),
      ),
    ),
  );

  Future<void> _jumpToEvent(String eventId) async {
    await widget.backend.jumpToEvent(eventId);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _messageKeys[eventId]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(target, alignment: 0.5);
      }
    });
  }

  void showMembers() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${widget.backend.selectedRoomMembers.length} members'),
      content: SizedBox(
        width: 360,
        height: 480,
        child: ListView(
          children: [
            for (final member in widget.backend.selectedRoomMembers)
              ListTile(
                dense: true,
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 15,
                      backgroundImage: member.avatarBytes == null
                          ? null
                          : MemoryImage(member.avatarBytes!),
                      child: member.avatarBytes == null
                          ? Text(member.displayName.characters.first)
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: switch (member.presence) {
                          UserPresence.online => const Color(0xff76d49b),
                          UserPresence.away => const Color(0xffffc857),
                          UserPresence.offline => const Color(0xff686a73),
                        },
                      ),
                    ),
                  ],
                ),
                title: Text(member.displayName),
                subtitle: Text(member.userId),
                onTap: () {
                  Navigator.of(context).pop();
                  showMemberProfile(this.context, widget.backend, member);
                },
              ),
          ],
        ),
      ),
    ),
  );

  DropOperation _onDropOver(DropOverEvent event) {
    if (!_draggingFiles) setState(() => _draggingFiles = true);
    return event.session.allowedOperations.contains(DropOperation.copy)
        ? DropOperation.copy
        : DropOperation.none;
  }

  void _onDropLeave(DropEvent _) {
    if (_draggingFiles) setState(() => _draggingFiles = false);
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final attachments = <AttachmentDraft>[];
    try {
      for (final item in event.session.items) {
        final reader = item.dataReader;
        if (reader == null) continue;
        final suggestedName = await reader.getSuggestedName();
        final completed = Completer<AttachmentDraft?>();
        final progress = reader.getFile(null, (file) async {
          try {
            final bytes = await file.readAll();
            final name = file.fileName ?? suggestedName ?? 'attachment';
            completed.complete(
              AttachmentDraft(
                bytes: bytes,
                name: name,
                mimeType:
                    lookupMimeType(name, headerBytes: bytes) ??
                    'application/octet-stream',
                spoiler: false,
              ),
            );
          } catch (_) {
            completed.complete(null);
          }
        }, onError: (_) => completed.complete(null));
        if (progress == null) continue;
        final attachment = await completed.future;
        if (attachment != null) attachments.add(attachment);
      }
      widget.onDropAttachments(attachments);
    } finally {
      if (mounted) setState(() => _draggingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final room = backend.selectedRoom!;
    final messages = backend.messages;
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onPerformDrop: _onPerformDrop,
      onDropLeave: _onDropLeave,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.centerLeft,
                  decoration: const BoxDecoration(
                    color: Color(0xff292a30),
                    border: Border(
                      bottom: BorderSide(color: Color(0xff35363d)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _RoomIcon(room: room, size: 30),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (room.topic.isNotEmpty)
                              Text(
                                room.topic,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xff989aa5),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '${backend.selectedRoomMembers.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xff989aa5),
                        ),
                      ),
                      if (backend.firstUnreadMessageId != null)
                        IconButton(
                          tooltip: 'Jump to first unread',
                          onPressed: _jumpToFirstUnread,
                          icon: const Icon(
                            Icons.mark_chat_unread_outlined,
                            size: 19,
                          ),
                        ),
                      IconButton(
                        tooltip: 'Search',
                        onPressed: showSearch,
                        icon: const Icon(Icons.search, size: 19),
                      ),
                      IconButton(
                        tooltip: 'Pinned messages',
                        onPressed: _showPins,
                        icon: const Icon(Icons.push_pin_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Members',
                        onPressed: showMembers,
                        icon: const Icon(Icons.people_outline, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Copy room link',
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: 'https://matrix.to/#/${room.id}'),
                        ),
                        icon: const Icon(Icons.link, size: 19),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Notification options',
                        icon: Icon(
                          backend.selectedRoomMuted
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_none,
                          size: 19,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'mute':
                              backend.setSelectedRoomMuted(
                                !backend.selectedRoomMuted,
                              );
                            case 'previews':
                              backend.setNotificationPreviewsEnabled(
                                !backend.notificationPreviewsEnabled,
                              );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'mute',
                            child: Text(
                              backend.selectedRoomMuted
                                  ? 'Unmute this room'
                                  : 'Mute this room',
                            ),
                          ),
                          CheckedPopupMenuItem(
                            value: 'previews',
                            checked: backend.notificationPreviewsEnabled,
                            child: const Text('Show message previews'),
                          ),
                        ],
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: backend.timelineLoading
                            ? const Center(child: CircularProgressIndicator())
                            : backend.messages.isEmpty
                            ? const Center(child: Text('No messages yet'))
                            : ListView.builder(
                                controller: _scrollController,
                                reverse: true,
                                padding: const EdgeInsets.fromLTRB(
                                  0,
                                  10,
                                  0,
                                  14,
                                ),
                                itemCount:
                                    messages.length +
                                    (backend.historyLoading ||
                                            backend.canLoadMoreHistory
                                        ? 1
                                        : 0),
                                itemBuilder: (context, index) {
                                  if (index == messages.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      child: Center(
                                        child: backend.historyLoading
                                            ? const SizedBox.square(
                                                dimension: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : TextButton.icon(
                                                onPressed: _loadOlderAnchored,
                                                icon: const Icon(
                                                  Icons.history,
                                                  size: 17,
                                                ),
                                                label: const Text(
                                                  'Load older messages',
                                                ),
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
                                      message.timestamp.difference(
                                            older.timestamp,
                                          ) >
                                          const Duration(minutes: 7) ||
                                      message.reply != null;
                                  return Column(
                                    key: _messageKeys.putIfAbsent(
                                      message.id,
                                      GlobalKey.new,
                                    ),
                                    children: [
                                      if (message.id ==
                                          backend.firstUnreadMessageId)
                                        const _UnreadDivider(),
                                      _MessageRow(
                                        message: message,
                                        startsGroup: startsGroup,
                                        onReply: () => widget.onReply(message),
                                        onEdit: message.own && !message.redacted
                                            ? () => widget.onEdit(message)
                                            : null,
                                        onDelete: message.canRedact
                                            ? () => _deleteMessage(message)
                                            : null,
                                        onReact:
                                            message.redacted || message.system
                                            ? null
                                            : () => _pickReaction(message),
                                        onRetry: message.failed
                                            ? () => backend.retryMessage(
                                                message.id,
                                              )
                                            : null,
                                        onCancel:
                                            message.pending || message.failed
                                            ? () =>
                                                  backend.cancelPendingMessage(
                                                    message.id,
                                                  )
                                            : null,
                                        onToggleReaction: (key) => backend
                                            .toggleReaction(message.id, key),
                                        backend: backend,
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                      if (!backend.atTimelinePresent)
                        Positioned(
                          right: 16,
                          bottom: 12,
                          child: FilledButton.tonalIcon(
                            onPressed: backend.jumpToPresent,
                            icon: const Icon(
                              Icons.vertical_align_bottom,
                              size: 17,
                            ),
                            label: const Text('Jump to present'),
                          ),
                        ),
                    ],
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
                if (widget.mentionSuggestions.isNotEmpty)
                  _MentionPicker(
                    suggestions: widget.mentionSuggestions,
                    selectedIndex: widget.mentionSelectionIndex,
                    onSelected: widget.onMentionSelected,
                  ),
                if (backend.typingUserNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(68, 2, 12, 0),
                    child: Text(
                      _typingLabel(backend.typingUserNames),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xffa7a9b4),
                      ),
                    ),
                  ),
                _RichComposer(
                  key: widget.composerKey,
                  controller: widget.controller,
                  focusNode: widget.composerFocus,
                  roomName: room.name,
                  enabled: !widget.sending,
                  sendWithCtrlEnter: backend.preferences.sendWithCtrlEnter,
                  onSend: widget.onSend,
                  onAttach: widget.onAttach,
                  onGif: widget.onGif,
                  onPasteImage: widget.onPasteImage,
                  pendingAttachments: widget.pendingAttachments,
                  onRemoveAttachment: widget.onRemoveAttachment,
                  onToggleAttachmentSpoiler: widget.onToggleAttachmentSpoiler,
                  mentionSuggestions: widget.mentionSuggestions,
                  mentionSelectionIndex: widget.mentionSelectionIndex,
                  onMentionSelected: widget.onMentionSelected,
                  onMentionSelectionChanged: widget.onMentionSelectionChanged,
                ),
              ],
            ),
          ),
          if (_draggingFiles)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xaa111216),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xff24252b),
                        border: Border.all(color: const Color(0xff858cff)),
                      ),
                      child: const Text('Drop files to attach'),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _typingLabel(List<String> names) {
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) {
      return '${names.first} and ${names.last} are typing…';
    }
    return '${names.first}, ${names[1]} and ${names.length - 2} others are typing…';
  }
}

class _RoomSearchDialog extends StatefulWidget {
  const _RoomSearchDialog({required this.backend, required this.onSelected});

  final ChatBackend backend;
  final ValueChanged<String> onSelected;

  @override
  State<_RoomSearchDialog> createState() => _RoomSearchDialogState();
}

class _RoomSearchDialogState extends State<_RoomSearchDialog> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = const [];
  bool _searching = false;
  String? _error;
  int _generation = 0;

  void _queryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.backend.searchRoomHistory(query);
      if (!mounted || generation != _generation) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = 'Search failed. Try again.');
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _searching = false);
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Search this room'),
    content: SizedBox(
      width: 520,
      height: 430,
      child: Column(
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search message history',
            ),
            onChanged: _queryChanged,
            onSubmitted: (_) {
              _debounce?.cancel();
              _search();
            },
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          if (_error != null) Text(_error!),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final message = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(message.sender),
                  subtitle: Text(
                    message.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelected(message.id);
                  },
                );
              },
            ),
          ),
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
