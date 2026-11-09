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
    required this.onSchedule,
    required this.onPoll,
    required this.onSticker,
    required this.onReply,
    required this.onEdit,
    required this.onCancelComposerAction,
    required this.onAttach,
    required this.onGif,
    required this.onPasteImage,
    required this.onDropAttachments,
    required this.pendingAttachments,
    required this.onRemoveAttachment,
    required this.onEditAttachment,
    required this.onToggleAttachmentSpoiler,
    required this.mentionSuggestions,
    required this.mentionSelectionIndex,
    required this.onMentionSelected,
    required this.onMentionSelectionChanged,
    required this.onShowMembers,
    this.onOpenDetails,
    required this.onShowProfile,
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
  final VoidCallback onSchedule;
  final VoidCallback onPoll;
  final VoidCallback onSticker;
  final ValueChanged<ChatMessage> onReply;
  final ValueChanged<ChatMessage> onEdit;
  final VoidCallback onCancelComposerAction;
  final VoidCallback onAttach;
  final VoidCallback onGif;
  final Future<bool> Function() onPasteImage;
  final ValueChanged<List<AttachmentDraft>> onDropAttachments;
  final List<AttachmentDraft> pendingAttachments;
  final ValueChanged<int> onRemoveAttachment;
  final ValueChanged<int> onEditAttachment;
  final ValueChanged<int> onToggleAttachmentSpoiler;
  final List<MentionSuggestion> mentionSuggestions;
  final int mentionSelectionIndex;
  final ValueChanged<String> onMentionSelected;
  final ValueChanged<int> onMentionSelectionChanged;
  final VoidCallback onShowMembers;
  final VoidCallback? onOpenDetails;
  final ValueChanged<(RoomMemberSummary, Offset?)> onShowProfile;
  final GlobalKey<_MessageComposerState> composerKey;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  static const _jumpToPresentScrollThreshold = 360.0;

  final _scrollController = ScrollController();
  final _timelineViewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  final _galleryRowKeys = GalleryRowKeys();
  String? _roomId;
  bool _loadingAnchoredHistory = false;
  bool _fillingInitialViewport = false;
  bool _draggingFiles = false;
  DropSession? _dropSession;
  final Set<DropItem> _checkedDropItems = {};
  final Set<DropItem> _localFileItems = {};
  bool _scrolledAwayFromPresent = false;
  DateTime _timelineUserInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _suppressPaginationUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool? _paginationTowardOlder;
  Timer? _edgeRetry;
  int _navigationGeneration = 0;
  int? _presentNavigation;
  String? get _composerTargetId =>
      widget.editingMessage?.id ?? widget.replyingTo?.id;
  int? _timelineLayoutFingerprint;
  int _layoutAnchorGeneration = 0;
  String? _newestMessageId;
  String? _highlightedMessageId;
  VoidCallback? _dismissMessageActions;

  @override
  void initState() {
    super.initState();
    _roomId = widget.backend.selectedRoom?.id;
    _newestMessageId = widget.backend.messages.firstOrNull?.id;
    _scrollController.addListener(_loadTimelineNearEdges);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
    _focusComposerAfterBuild();
  }

  void _focusComposerAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.sending) widget.composerFocus.requestFocus();
    });
  }

  void _loadTimelineNearEdges() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    widget.backend.setConversationAtPresent(
      position.pixels <= 48 && widget.backend.atTimelinePresent,
    );
    final scrolledAway = position.pixels > _jumpToPresentScrollThreshold;
    if (scrolledAway != _scrolledAwayFromPresent && mounted) {
      setState(() => _scrolledAwayFromPresent = scrolledAway);
    }
    // Content insertion, eviction, and anchor restoration all update scroll
    // metrics. Only paginate automatically while the user is actively moving
    // toward that edge; otherwise one page can recursively trigger another.
    final isUserDriven = DateTime.now().isBefore(_timelineUserInputUntil);
    final paginationSuppressed = DateTime.now().isBefore(
      _suppressPaginationUntil,
    );
    if (_presentNavigation != null) return;
    if (paginationSuppressed && isUserDriven && _edgeRetry == null) {
      final room = _roomId;
      _edgeRetry = Timer(
        _suppressPaginationUntil.difference(DateTime.now()) +
            const Duration(milliseconds: 1),
        () {
          _edgeRetry = null;
          if (mounted && room == _roomId) {
            // Timer expiry is monotonic, even if the wall clock changes.
            _suppressPaginationUntil = DateTime.fromMillisecondsSinceEpoch(0);
            _loadTimelineNearEdges();
          }
        },
      );
    }
    final older =
        _paginationTowardOlder ??
        (position.userScrollDirection == ScrollDirection.reverse);
    if (!paginationSuppressed &&
        isUserDriven &&
        older &&
        widget.backend.canLoadMoreHistory &&
        !widget.backend.historyLoading &&
        position.pixels >= position.maxScrollExtent - 240) {
      _loadOlderAnchored();
    } else if (!paginationSuppressed &&
        isUserDriven &&
        !older &&
        position.pixels <= 240 &&
        widget.backend.canLoadMoreFuture) {
      _loadNewerAnchored();
    }
  }

  void _noteTimelineUserInput(PointerEvent event) {
    if (event is PointerDownEvent) _paginationTowardOlder = null;
    if (_presentNavigation != null) {
      _navigationGeneration++;
      setState(() => _presentNavigation = null);
    }
    _timelineUserInputUntil = DateTime.now().add(const Duration(seconds: 2));
  }

  void _noteTimelineSignal(PointerSignalEvent event) {
    _noteTimelineUserInput(event);
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
      _paginationTowardOlder = event.scrollDelta.dy < 0;
      _loadTimelineNearEdges();
    }
  }

  void _noteTimelinePan(PointerPanZoomUpdateEvent event) {
    _noteTimelineUserInput(event);
    if (event.panDelta.dy != 0) {
      _paginationTowardOlder = event.panDelta.dy > 0;
      _loadTimelineNearEdges();
    }
  }

  SegmentTimelineAnchor? _captureVisibleAnchor() =>
      captureSegmentTimelineAnchor(
        _timelineViewportKey,
        _messageKeys,
        widget.backend.timelineSegmentId,
      );

  void _restoreVisibleAnchor(SegmentTimelineAnchor? anchor) =>
      restoreSegmentTimelineAnchor(
        _scrollController,
        _messageKeys,
        anchor,
        widget.backend.timelineSegmentId,
      );

  Future<void> _loadPageAnchored(
    Future<void> Function(String? anchorEventId) load,
  ) async {
    if (_loadingAnchoredHistory || !_scrollController.hasClients) return;
    _loadingAnchoredHistory = true;
    final anchor = _captureVisibleAnchor();
    final navigation = _navigationGeneration;
    final inputUntil = _timelineUserInputUntil;
    _edgeRetry?.cancel();
    _edgeRetry = null;
    _suppressPaginationUntil = DateTime.now().add(
      const Duration(milliseconds: 700),
    );
    try {
      await load(null);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted &&
          navigation == _navigationGeneration &&
          _presentNavigation == null &&
          inputUntil == _timelineUserInputUntil) {
        _restoreVisibleAnchor(anchor);
      }
    } catch (_) {
      // The backend reports its user-facing pagination error separately.
    } finally {
      _loadingAnchoredHistory = false;
      if (mounted && navigation == _navigationGeneration) {
        _loadTimelineNearEdges();
      }
    }
  }

  Future<void> _loadOlderAnchored() => _loadPageAnchored(
    (anchorEventId) =>
        widget.backend.loadMoreHistory(anchorEventId: anchorEventId),
  );

  Future<void> _loadNewerAnchored() => _loadPageAnchored(
    (anchorEventId) =>
        widget.backend.loadMoreFuture(anchorEventId: anchorEventId),
  );

  void _scheduleInitialViewportFill() {
    if (_fillingInitialViewport || widget.backend.timelineLoading) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_fillInitialViewport());
    });
  }

  Future<void> _fillInitialViewport() async {
    if (_fillingInitialViewport || !_scrollController.hasClients) return;
    if (!widget.backend.atTimelinePresent || _scrollController.offset > 48) {
      return;
    }
    _fillingInitialViewport = true;
    final roomId = widget.backend.selectedRoom?.id;
    try {
      for (var pass = 0; pass < 4; pass++) {
        if (!mounted ||
            roomId != widget.backend.selectedRoom?.id ||
            !widget.backend.canLoadMoreHistory ||
            _scrollController.position.maxScrollExtent > 8) {
          break;
        }
        final previousCount = widget.backend.messages.length;
        await widget.backend.loadMoreHistory();
        if (!mounted || widget.backend.messages.length <= previousCount) break;
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _fillingInitialViewport = false;
    }
  }

  int _layoutFingerprint(List<ChatMessage> messages) => Object.hashAll(
    messages.map(
      (message) => Object.hash(
        message.id,
        message.reply?.eventId,
        message.linkPreviews.length,
        message.linkPreview?.width,
        message.linkPreview?.height,
        message.reactions.length,
      ),
    ),
  );

  void _preserveAnchorAcrossMetadataLayout(List<ChatMessage> messages) {
    final next = _layoutFingerprint(messages);
    final previous = _timelineLayoutFingerprint;
    _timelineLayoutFingerprint = next;
    if (previous == null ||
        previous == next ||
        _presentNavigation != null ||
        _loadingAnchoredHistory ||
        !_scrolledAwayFromPresent ||
        DateTime.now().isBefore(_timelineUserInputUntil)) {
      return;
    }
    final anchor = _captureVisibleAnchor();
    if (anchor == null) return;
    final generation = ++_layoutAnchorGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _layoutAnchorGeneration) return;
      _restoreVisibleAnchor(anchor);
    });
  }

  Future<void> _jumpToFirstUnread() async {
    final eventId = widget.backend.firstUnreadMessageId;
    if (eventId == null || !_scrollController.hasClients) return;
    await _jumpToEvent(eventId);
  }

  Future<void> _returnToPresent() async {
    if (_presentNavigation != null) return;
    final generation = ++_navigationGeneration;
    _layoutAnchorGeneration++;
    _timelineUserInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _suppressPaginationUntil = DateTime.now().add(const Duration(seconds: 1));
    setState(() => _presentNavigation = generation);
    try {
      await widget.backend.jumpToPresent();
      await scrollToTimelinePresent(
        controller: _scrollController,
        isCurrent: () =>
            mounted &&
            generation == _navigationGeneration &&
            widget.backend.atTimelinePresent,
        reducedMotion: widget.backend.preferences.reducedMotion,
      );
      if (mounted &&
          generation == _navigationGeneration &&
          widget.backend.atTimelinePresent) {
        setState(() => _scrolledAwayFromPresent = false);
        _reportTimelineAtPresent();
      }
    } finally {
      if (mounted && _presentNavigation == generation) {
        setState(() => _presentNavigation = null);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _Conversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roomId = widget.backend.selectedRoom?.id;
    final newestMessageId = widget.backend.messages.firstOrNull?.id;
    final receivedNewHead =
        _roomId == roomId &&
        _newestMessageId != null &&
        newestMessageId != null &&
        newestMessageId != _newestMessageId;
    final wasAtPresent =
        !_scrolledAwayFromPresent &&
        (!_scrollController.hasClients || _scrollController.offset <= 48);
    if (_roomId != roomId) {
      _edgeRetry?.cancel();
      _edgeRetry = null;
      _paginationTowardOlder = null;
      _timelineUserInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
      _draggingFiles = false;
      _clearDropSession();
      widget.backend.setConversationAtPresent(false);
      _roomId = roomId;
      _scrolledAwayFromPresent = false;
      _messageKeys.clear();
      _navigationGeneration++;
      _presentNavigation = null;
      _highlightedMessageId = null;
      _newestMessageId = newestMessageId;
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
      _focusComposerAfterBuild();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reportTimelineAtPresent(),
      );
    } else if (oldWidget.sending && !widget.sending) {
      _focusComposerAfterBuild();
    }
    _newestMessageId = newestMessageId;
    if (receivedNewHead && wasAtPresent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _roomId != roomId || !_scrollController.hasClients) {
          return;
        }
        // In a reversed timeline offset zero is the present. A live event is
        // already inserted there, so keep the viewport pinned without an
        // animated correction that can flash the previous row first.
        _scrollController.jumpTo(0);
      });
    }
  }

  GlobalKey _messageKeyFor(ChatMessage message) {
    final key = _messageKeys.putIfAbsent(message.timelineKey, GlobalKey.new);
    _messageKeys[message.id] = key;
    return key;
  }

  @override
  void dispose() {
    _edgeRetry?.cancel();
    _dropSession?.onDisposed.removeListener(_clearDropSession);
    widget.backend.setConversationAtPresent(false);
    _scrollController.dispose();
    super.dispose();
  }

  void _reportTimelineAtPresent() {
    if (!mounted) return;
    widget.backend.setConversationAtPresent(
      widget.backend.atTimelinePresent &&
          (!_scrollController.hasClients || _scrollController.offset <= 48),
    );
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final albums = MediaAlbumIndex.fromNewestFirst(widget.backend.messages);
    await deleteMessageGroup(
      context,
      widget.backend,
      albums.albums[message.id] ?? [message],
    );
    _focusComposerAfterBuild();
  }

  Future<void> _pickReaction(ChatMessage message) async {
    final emoji = await showDialog<EmojiEntry>(
      context: context,
      builder: (context) => EmojiPickerDialog(backend: widget.backend),
    );
    if (emoji != null) {
      await widget.backend.toggleReaction(
        message.id,
        emoji.emoji,
        customEmoji: emoji.customEmoji?.customEmoji,
      );
    }
    _focusComposerAfterBuild();
  }

  Future<void> showSearch() async {
    await showRoomSearchDialog(context, widget.backend, onOpen: _jumpToEvent);
    _focusComposerAfterBuild();
  }

  Future<void> _showPins() async {
    final messages = await widget.backend.loadPinnedMessages();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pinned messages'),
        content: SizedBox(
          width: 460,
          child: messages.isEmpty
              ? const Text('No pinned messages')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final message in messages)
                      ListTile(
                        dense: true,
                        title: Text(message.sender),
                        subtitle: Text(message.body),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          _jumpToEvent(message.id);
                        },
                      ),
                  ],
                ),
        ),
      ),
    );
    _focusComposerAfterBuild();
  }

  Future<void> _jumpToEvent(String eventId) async {
    _presentNavigation = null;
    final generation = ++_navigationGeneration;
    _suppressPaginationUntil = DateTime.now().add(const Duration(seconds: 1));
    if (!await _scrollToMessage(eventId, generation)) {
      await widget.backend.jumpToEvent(eventId);
      if (!mounted || generation != _navigationGeneration) return;
      await _scrollToMessage(eventId, generation, waitForBuild: true);
    }
    if (!mounted || generation != _navigationGeneration) return;
    await _blinkMessage(
      MediaAlbumIndex.fromNewestFirst(
        widget.backend.timelineMessages,
      ).visibleMessageId(eventId),
      generation,
    );
  }

  Future<bool> _scrollToMessage(
    String eventId,
    int generation, {
    bool waitForBuild = false,
  }) async {
    if (waitForBuild) await WidgetsBinding.instance.endOfFrame;
    if (!mounted || generation != _navigationGeneration) return false;
    final messages = widget.backend.timelineMessages;
    final target = MediaAlbumIndex.fromNewestFirst(
      messages,
    ).visibleMessageId(eventId);
    return scrollToTimelineRow(
      controller: _scrollController,
      rowKeys: _messageKeys,
      ids: messages.map((m) => m.id).toList(),
      id: target,
      isCurrent: () => mounted && generation == _navigationGeneration,
      reducedMotion: widget.backend.preferences.reducedMotion,
    );
  }

  Future<void> _blinkMessage(String eventId, int generation) async {
    for (var pulse = 0; pulse < 2; pulse++) {
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _highlightedMessageId = eventId);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted || generation != _navigationGeneration) return;
      setState(() => _highlightedMessageId = null);
      if (pulse == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 110));
      }
    }
  }

  void showMembers() {
    widget.onShowMembers();
    _focusComposerAfterBuild();
  }

  bool dismissTemporaryUi() {
    final dismiss = _dismissMessageActions;
    if (dismiss == null) return false;
    _dismissMessageActions = null;
    dismiss();
    return true;
  }

  void _registerMessageActions(VoidCallback dismiss) {
    _dismissMessageActions?.call();
    _dismissMessageActions = dismiss;
  }

  DropOperation _onDropOver(DropOverEvent event) {
    if (!identical(_dropSession, event.session)) {
      _dropSession?.onDisposed.removeListener(_clearDropSession);
      _dropSession = event.session;
      _checkedDropItems.clear();
      _localFileItems.clear();
      event.session.onDisposed.addListener(_clearDropSession);
    }
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader != null &&
          item.canProvide(Formats.fileUri) &&
          _checkedDropItems.add(item)) {
        reader.getValue(Formats.fileUri, (uri) {
          if (mounted &&
              identical(_dropSession, event.session) &&
              uri != null) {
            _localFileItems.add(item);
            if (event.session.allowedOperations.contains(DropOperation.copy)) {
              setState(() => _draggingFiles = true);
            }
          }
        }, onError: (_) {});
      }
    }
    final accepts =
        event.session.allowedOperations.contains(DropOperation.copy) &&
        event.session.items.any(
          (item) =>
              _localFileItems.contains(item) ||
              Formats.standardFormats
                  .whereType<FileFormat>()
                  .where(
                    (format) =>
                        format != Formats.plainTextFile &&
                        format != Formats.htmlFile,
                  )
                  .any(item.canProvide),
        );
    if (_draggingFiles != accepts) setState(() => _draggingFiles = accepts);
    return accepts ? DropOperation.copy : DropOperation.none;
  }

  void _onDropLeave(DropEvent _) {
    _clearDropSession();
  }

  void _clearDropSession() {
    _dropSession?.onDisposed.removeListener(_clearDropSession);
    _dropSession = null;
    _checkedDropItems.clear();
    _localFileItems.clear();
    if (mounted && _draggingFiles) setState(() => _draggingFiles = false);
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final roomId = widget.backend.selectedRoom?.id;
    _clearDropSession();
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
      if (mounted && widget.backend.selectedRoom?.id == roomId) {
        widget.onDropAttachments(attachments);
      }
    } finally {
      if (mounted) setState(() => _draggingFiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backend = widget.backend;
    final room = backend.selectedRoom!;
    final messages = backend.timelineMessages;
    final receipts = receiptFrontiers(messages);
    final mediaAlbums = MediaAlbumIndex.fromNewestFirst(
      messages,
      roomId: room.id,
      segmentId: backend.timelineSegmentId,
    );
    _galleryRowKeys.bind(mediaAlbums, _messageKeys);
    _scheduleInitialViewportFill();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reportTimelineAtPresent(),
    );
    _preserveAnchorAcrossMetadataLayout(messages);
    final retainedIds = messages
        .expand((message) => [message.id, message.timelineKey])
        .toSet();
    _messageKeys.removeWhere((eventId, _) => !retainedIds.contains(eventId));
    final messageIndexes = <String, int>{
      for (var index = 0; index < messages.length; index++)
        mediaAlbums.rowIdentity(messages[index]): index,
    };
    final mediaMessages = messages
        .where(
          (message) =>
              message.attachment?.kind == AttachmentKind.image ||
              message.attachment?.kind == AttachmentKind.video,
        )
        .toList(growable: false);
    return ReceiptPlacement(
      messages: messages,
      receiptIds: receipts,
      hiddenIds: mediaAlbums.hiddenMessageIds,
      contentInset: 80,
      child: DropRegion(
        formats: Formats.standardFormats,
        hitTestBehavior: HitTestBehavior.opaque,
        onDropOver: _onDropOver,
        onPerformDrop: _onPerformDrop,
        onDropLeave: _onDropLeave,
        onDropEnded: _onDropLeave,
        child: Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  ThemeSurface(
                    color: context.deltiecord.surface,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 56),
                      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          if (_DesktopNavigation.of(context)?.openRooms
                              case final open?)
                            IconButton(
                              tooltip: 'Show chats',
                              icon: const Icon(Icons.menu),
                              onPressed: open,
                            ),
                          if (!room.usesChannelIcon) ...[
                            _RoomIcon(
                              key: const ValueKey('conversation-header-avatar'),
                              room: room,
                              size: 38,
                              showPresence:
                                  room.isDirect && !room.usesChannelIcon,
                              autoplay: true,
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onOpenDetails,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    room.name,
                                    key: const ValueKey(
                                      'conversation-header-name',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: DeltiecordTypeScale.bigUi,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (room.isDirect)
                                    TimelineActivityStatus(
                                      status: room.statusMessage,
                                      backend: backend,
                                      userId: room.directUserId,
                                      presence: room.presence,
                                      fallback: _ConversationPresence(
                                        presence: room.presence,
                                      ),
                                    )
                                  else if (room.topic.isNotEmpty)
                                    Text(
                                      room.topic,
                                      key: const ValueKey(
                                        'conversation-header-topic',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: DeltiecordTypeScale.normal,
                                        color: context.deltiecord.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Search',
                            onPressed: showSearch,
                            icon: const ThemeIcon(Icons.search),
                          ),
                          IconButton(
                            tooltip: backend.activeVoiceRoomId != null
                                ? 'Disconnect'
                                : 'Start call',
                            onPressed: () => backend.activeVoiceRoomId != null
                                ? backend.leaveVoiceRoom()
                                : backend.joinVoiceRoom(room.id),
                            icon: ThemeIcon(
                              backend.activeVoiceRoomId != null
                                  ? Icons.call_end
                                  : Icons.call_outlined,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Room tools',
                            icon: const ThemeIcon(Icons.more_horiz, size: 22),
                            onSelected: (value) async {
                              switch (value) {
                                case 'events':
                                  await showRoomEventVisibility(
                                    context,
                                    backend,
                                    room.id,
                                  );
                                case 'access':
                                  await showRoomAccessDialog(
                                    context,
                                    backend,
                                    room.id,
                                    spaceId: backend.selectedRoomSpaceId,
                                  );
                                case 'notifications':
                                  await showRoomNotificationControls(
                                    context,
                                    backend,
                                    room,
                                  );
                                case 'search':
                                  showSearch();
                                case 'pins':
                                  _showPins();
                                case 'members':
                                  widget.onShowMembers();
                                case 'call':
                                  backend.joinVoiceRoom(room.id);
                                case 'copy-link':
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: 'https://matrix.to/#/${room.id}',
                                    ),
                                  );
                                case 'first-unread':
                                  _jumpToFirstUnread();
                                case 'saved':
                                  await showSavedMessages(
                                    context,
                                    backend,
                                    onOpen: (roomId, eventId) async {
                                      if (backend.selectedRoom?.id != roomId) {
                                        await backend.selectRoom(roomId);
                                      }
                                      await backend.jumpToEvent(eventId);
                                    },
                                  );
                                case 'media':
                                  await showRoomSearchDialog(
                                    context,
                                    backend,
                                    onOpen: _jumpToEvent,
                                    initialSection: RoomSearchSection.media,
                                  );
                                case 'inbox':
                                  await showUnifiedInbox(
                                    context,
                                    backend,
                                    onOpen: (item) async {
                                      if (backend.selectedRoom?.id !=
                                          item.roomId) {
                                        await backend.selectRoom(item.roomId);
                                      }
                                      if (item.eventId != null) {
                                        await backend.jumpToEvent(
                                          item.eventId!,
                                        );
                                      }
                                    },
                                  );
                                case 'all':
                                  backend.setRoomNotificationMode(
                                    room.id,
                                    RoomNotificationMode.allMessages,
                                  );
                                case 'mentions':
                                  backend.setRoomNotificationMode(
                                    room.id,
                                    RoomNotificationMode.mentionsOnly,
                                  );
                                case 'mute':
                                  backend.setRoomNotificationMode(
                                    room.id,
                                    RoomNotificationMode.muted,
                                  );
                                case 'hour':
                                  backend.muteRoomUntil(
                                    room.id,
                                    DateTime.now().add(
                                      const Duration(hours: 1),
                                    ),
                                  );
                                case 'tomorrow':
                                  final now = DateTime.now();
                                  backend.muteRoomUntil(
                                    room.id,
                                    DateTime(
                                      now.year,
                                      now.month,
                                      now.day + 1,
                                      9,
                                    ),
                                  );
                                case 'unread':
                                  backend.markRoomUnread(
                                    room.id,
                                    !room.markedUnread,
                                  );
                                case 'invite':
                                  showInviteMember(context, backend);
                                case 'aliases':
                                  showRoomAliasEditor(context, backend, room);
                                case 'previews':
                                  backend.setNotificationPreviewsEnabled(
                                    !backend.notificationPreviewsEnabled,
                                  );
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'pins',
                                child: Text('Pinned messages'),
                              ),
                              const PopupMenuItem(
                                value: 'members',
                                child: Text('Members'),
                              ),

                              if (backend.firstUnreadMessageId != null)
                                const PopupMenuItem(
                                  value: 'first-unread',
                                  child: Text('Jump to first unread'),
                                ),

                              const PopupMenuItem(
                                value: 'saved',
                                child: Text('Saved and scheduled'),
                              ),

                              const PopupMenuDivider(),

                              const PopupMenuItem(
                                value: 'notifications',
                                child: Text('Notification settings'),
                              ),
                              const PopupMenuItem(
                                value: 'events',
                                child: Text('Timeline events'),
                              ),
                              if (!room.isDirect)
                                const PopupMenuItem(
                                  value: 'access',
                                  child: Text(
                                    'Room access and shared settings',
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
                  EncryptionAttentionBanner(backend: backend, room: room),
                  Expanded(
                    child: Stack(
                      key: const Key('conversation-timeline-area'),
                      children: [
                        Positioned.fill(
                          child: KeyedSubtree(
                            key: _timelineViewportKey,
                            child: Listener(
                              onPointerDown: _noteTimelineUserInput,
                              onPointerMove: _noteTimelineUserInput,
                              onPointerSignal: _noteTimelineSignal,
                              onPointerPanZoomStart: _noteTimelineUserInput,
                              onPointerPanZoomUpdate: _noteTimelinePan,
                              child: backend.timelineLoading && messages.isEmpty
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : messages.isEmpty
                                  ? const Center(child: Text('No messages yet'))
                                  : ListView.builder(
                                      key: const Key('message-timeline'),
                                      controller: _scrollController,
                                      reverse: true,
                                      physics: const ClampingScrollPhysics(),
                                      padding: EdgeInsets.fromLTRB(
                                        0,
                                        10,
                                        0,
                                        typingIndicatorHeightFor(context) + 1,
                                      ),
                                      itemCount:
                                          messages.length +
                                          (backend.historyLoading ||
                                                  backend.canLoadMoreHistory
                                              ? 1
                                              : 0),
                                      findChildIndexCallback: (key) {
                                        final messageId =
                                            key is ValueKey<String>
                                            ? key.value
                                            : null;
                                        if (messageId == null) return null;
                                        return messageIndexes[messageId];
                                      },
                                      itemBuilder: (context, index) {
                                        if (index == messages.length) {
                                          return SizedBox(
                                            height: 64,
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
                                                      onPressed:
                                                          _loadOlderAnchored,
                                                      icon: const ThemeIcon(
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
                                        if (mediaAlbums.hiddenMessageIds
                                            .contains(message.id)) {
                                          return SizedBox.shrink(
                                            key: ValueKey(
                                              mediaAlbums.rowIdentity(message),
                                            ),
                                          );
                                        }
                                        final older = mediaAlbums
                                            .olderVisibleMessage(message.id);
                                        final startsGroup =
                                            mediaAlbums.albums.containsKey(
                                              message.id,
                                            ) ||
                                            older == null ||
                                            !DateUtils.isSameDay(
                                              older.timestamp.toLocal(),
                                              message.timestamp.toLocal(),
                                            ) ||
                                            older.system ||
                                            message.system ||
                                            older.senderId !=
                                                message.senderId ||
                                            message.timestamp.difference(
                                                  older.timestamp,
                                                ) >
                                                const Duration(minutes: 7) ||
                                            message.reply != null;
                                        return Column(
                                          key: ValueKey(
                                            mediaAlbums.rowIdentity(message),
                                          ),
                                          children: [
                                            if (older == null ||
                                                !DateUtils.isSameDay(
                                                  older.timestamp.toLocal(),
                                                  message.timestamp.toLocal(),
                                                ))
                                              MessageDaySeparator(
                                                date: message.timestamp,
                                              ),
                                            if (message.id ==
                                                mediaAlbums.visibleMessageId(
                                                  backend.firstUnreadMessageId ??
                                                      '',
                                                ))
                                              const _UnreadDivider(),
                                            _MessageRow(
                                              key: _messageKeyFor(message),
                                              message: message,
                                              receiptIds: receipts,
                                              showReceipt: receipts.contains(
                                                message.id,
                                              ),
                                              albumMessages: mediaAlbums
                                                  .albums[message.id],
                                              highlighted:
                                                  _highlightedMessageId ==
                                                  message.id,
                                              replying:
                                                  _composerTargetId ==
                                                      message.id ||
                                                  (mediaAlbums
                                                          .albums[message.id]
                                                          ?.any(
                                                            (m) =>
                                                                m.id ==
                                                                _composerTargetId,
                                                          ) ??
                                                      false),
                                              startsGroup: startsGroup,
                                              onReply: () =>
                                                  widget.onReply(message),
                                              onEdit:
                                                  message.own &&
                                                      !message.redacted
                                                  ? () => widget.onEdit(message)
                                                  : null,
                                              onDelete:
                                                  message.own &&
                                                      message.canRedact
                                                  ? () =>
                                                        _deleteMessage(message)
                                                  : null,
                                              onReact:
                                                  message.redacted ||
                                                      message.system
                                                  ? null
                                                  : () =>
                                                        _pickReaction(message),
                                              onRetry: message.failed
                                                  ? () => backend.retryMessage(
                                                      message.id,
                                                    )
                                                  : null,
                                              onCancel:
                                                  message.pending ||
                                                      message.failed
                                                  ? () => backend
                                                        .cancelPendingMessage(
                                                          message.id,
                                                        )
                                                  : null,
                                              onToggleReaction: (reaction) =>
                                                  backend.toggleReaction(
                                                    message.id,
                                                    reaction.key,
                                                    customEmoji:
                                                        reaction.customEmoji,
                                                  ),
                                              onJumpToReply: _jumpToEvent,
                                              mediaMessages: mediaMessages,
                                              backend: backend,
                                              onShowProfile:
                                                  widget.onShowProfile,
                                              onActionsShown:
                                                  _registerMessageActions,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ),
                        if (backend.timelineLoading && messages.isNotEmpty)
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (!backend.atTimelinePresent ||
                            _scrolledAwayFromPresent)
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: FilledButton.tonalIcon(
                              key: const ValueKey('jump-to-present'),
                              onPressed: _presentNavigation == null
                                  ? _returnToPresent
                                  : null,
                              icon: const ThemeIcon(
                                Icons.vertical_align_bottom,
                                size: 17,
                              ),
                              label: Text(
                                room.unreadCount > 0
                                    ? 'Jump to present (${room.unreadCount})'
                                    : 'Jump to present',
                              ),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: TypingIndicator(
                            names: backend.typingUserNames,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.replyingTo case final message?)
                    _ComposerContext(
                      label: 'Replying to ${message.sender}',
                      body: message.body,
                      onTap: () => _jumpToEvent(message.id),
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
                  if (!backend.canSendMessagesToRoom(room.id))
                    const ReadOnlyConversationNotice()
                  else
                    VoiceMessageComposer(
                      key: ValueKey('voice-composer-${room.id}'),
                      backend: backend,
                      roomId: room.id,
                      replyToMessageId: widget.replyingTo?.id,
                      onSent: widget.onCancelComposerAction,
                      builder: (startRecording) => _MessageComposer(
                        onEscape: widget.editingMessage == null
                            ? null
                            : () {
                                dismissTemporaryUi();
                                widget.onCancelComposerAction();
                              },
                        key: widget.composerKey,
                        backend: backend,
                        controller: widget.controller,
                        focusNode: widget.composerFocus,
                        roomName: room.name,
                        sending: widget.sending,
                        replyToMessageId: widget.replyingTo?.id,
                        // The editor remains live while this only gates attachment
                        // and submit controls for the in-flight request.
                        enabled: true,
                        sendWithCtrlEnter:
                            backend.preferences.sendWithCtrlEnter,
                        onSend: widget.onSend,
                        onRecord: widget.editingMessage == null
                            ? startRecording
                            : null,
                        onSchedule: widget.onSchedule,
                        onPoll: widget.onPoll,
                        onSticker: widget.onSticker,
                        onAttach: widget.onAttach,
                        onGif: widget.onGif,
                        onPasteImage: widget.onPasteImage,
                        pendingAttachments: widget.pendingAttachments,
                        onRemoveAttachment: widget.onRemoveAttachment,
                        onEditAttachment: widget.onEditAttachment,
                        onToggleAttachmentSpoiler:
                            widget.onToggleAttachmentSpoiler,
                        mentionSuggestions: widget.mentionSuggestions,
                        mentionSelectionIndex: widget.mentionSelectionIndex,
                        onMentionSelected: widget.onMentionSelected,
                        onMentionSelectionChanged:
                            widget.onMentionSelectionChanged,
                        maxHeight: max(
                          _bottomPanelHeightFor(context),
                          (MediaQuery.sizeOf(context).height - 56) / 3,
                        ),
                      ),
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
                          color: context.deltiecord.elevated,
                          borderRadius: DeltiecordCorners.borderRadius,
                        ),
                        child: const Text('Drop files to attach'),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConversationPresence extends StatelessWidget {
  const _ConversationPresence({required this.presence});

  final UserPresence presence;

  @override
  Widget build(BuildContext context) {
    final label = switch (presence) {
      UserPresence.online => 'Online',
      UserPresence.away => 'Away',
      UserPresence.doNotDisturb => 'Do not disturb',
      UserPresence.offline => 'Offline',
    };
    return Semantics(
      label: 'Presence: $label',
      child: Row(
        key: ValueKey('conversation-presence-${presence.name}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: DeltiecordTypeScale.small,
              color: context.deltiecord.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ThemeIcon(Icons.forum_outlined, size: 46),
        SizedBox(height: 12),
        Text('Choose a room to start chatting'),
      ],
    ),
  );
}
