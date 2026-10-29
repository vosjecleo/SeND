part of 'chat_shell.dart';

void openDiscussion(
  BuildContext context,
  ChatBackend backend,
  ChatMessage message,
) {
  final roomId =
      backend.roomIdForMessage(message.id) ?? backend.selectedRoom?.id;
  if (roomId == null) return;
  final rootId = message.threadRootId ?? message.id;
  openDiscussionById(context, backend, roomId, rootId);
}

void openDiscussionById(
  BuildContext context,
  ChatBackend backend,
  String roomId,
  String rootId,
) {
  final shell = context.findAncestorStateOfType<_ChatShellState>();
  if (shell != null && MediaQuery.sizeOf(context).width >= 1100) {
    shell._openDiscussion(rootId);
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: ThreadView(
            backend: backend,
            roomId: roomId,
            rootId: rootId,
            onClose: () => Navigator.pop(context),
          ),
        ),
      ),
    ),
  );
}

class ThreadView extends StatefulWidget {
  const ThreadView({
    super.key,
    required this.backend,
    required this.roomId,
    required this.rootId,
    required this.onClose,
  });
  final ChatBackend backend;
  final String roomId;
  final String rootId;
  final VoidCallback onClose;
  @override
  State<ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<ThreadView> with WidgetsBindingObserver {
  final _draft = QuillController.basic();
  final _composer = GlobalKey<_MessageComposerState>();
  final _attachments = <AttachmentDraft>[];
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _viewportKey = GlobalKey();
  final _rowKeys = <String, GlobalKey>{};
  DateTime _userInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
  ThreadSession? _session;
  String? _error;
  ChatMessage? _editing;
  ChatMessage? _replying;
  bool _sending = false;
  int? _mentionStart;
  String? _mentionQuery;
  int _mentionIndex = 0;
  int _replyJumpGeneration = 0;
  String? _highlightedMessage;
  List<MentionSuggestion> get _mentions => matchingComposerMentions(
    widget.backend.mentionSuggestions,
    _mentionQuery,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_acknowledge);
    _scroll.addListener(_loadNearEdge);
    _draft.addListener(_typingChanged);
    _open();
  }

  void _typingChanged() {
    unawaited(
      _session?.setTyping(_draft.document.toPlainText().trim().isNotEmpty),
    );
    final text = _draft.document.toPlainText();
    final match = composerMentionQuery(text, _draft.selection.extentOffset);
    final query = match?.query;
    if ((query != _mentionQuery || match?.start != _mentionStart) && mounted) {
      setState(() {
        _mentionQuery = query;
        _mentionStart = match?.start;
        _mentionIndex = 0;
      });
    }
  }

  void _insertMention(String id) {
    final start = _mentionStart;
    final suggestion = _mentions.where((m) => m.matrixId == id).firstOrNull;
    if (start == null || suggestion == null) return;
    insertComposerMention(_draft, start, suggestion);
    _focus.requestFocus();
  }

  Future<void> _sticker() async {
    final session = _session;
    if (session == null) return;
    final sticker = await showStickerPicker(context, widget.backend);
    if (sticker != null && mounted) {
      await _run(
        () => widget.backend.enqueueRoomSend(
          widget.roomId,
          () => session.sendSticker(sticker),
        ),
      );
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (session == null) return;
    final poll = await showPollComposer(context);
    if (poll != null && mounted) {
      await _run(
        () => widget.backend.enqueueRoomSend(
          widget.roomId,
          () => session.sendPoll(poll),
        ),
      );
    }
  }

  Future<void> _schedule() async {
    final session = _session;
    final text = serializePlainComposer(_draft.document).plainText.trim();
    if (session == null ||
        text.isEmpty ||
        _editing != null ||
        _attachments.isNotEmpty) {
      return;
    }
    final at = await showSchedulePicker(context);
    if (at == null || !mounted) return;
    await _run(
      () => session.schedule(text, at, replyToMessageId: _replying?.id),
    );
    if (mounted && _error == null) {
      setState(() {
        resetRichComposer(_draft);
        _replying = null;
      });
    }
  }

  void _replaceDraft(String text, [String? html]) {
    _draft.document = plainMessageDocument(text, html);
    _draft.updateSelection(
      TextSelection.collapsed(offset: text.length),
      ChangeSource.local,
    );
  }

  void _reply(ChatMessage message) {
    setState(() {
      _replying = message;
      _editing = null;
    });
    _focus.requestFocus();
  }

  Future<void> _jumpToReply(String id) async {
    final session = _session;
    if (session == null) return;
    final generation = ++_replyJumpGeneration;
    bool current() =>
        mounted &&
        generation == _replyJumpGeneration &&
        identical(session, _session);
    // Keep the server's relation cursor; never invent a partial thread window
    // from unrelated room-context events. Further history stays manually paged.
    for (
      var page = 0;
      page < 8 &&
          !session.messages.any((m) => m.id == id) &&
          session.canLoadMore &&
          !session.loading;
      page++
    ) {
      await session.loadMore();
      if (!current() || session.error != null) return;
    }
    if (!current()) return;
    final messages = session.messages;
    final target = MediaAlbumIndex.fromNewestFirst(
      messages,
    ).visibleMessageId(id);
    _userInputUntil = DateTime.fromMillisecondsSinceEpoch(0);
    final found = await scrollToTimelineRow(
      controller: _scroll,
      rowKeys: _rowKeys,
      ids: messages.map((m) => m.id).toList(),
      id: target,
      isCurrent: current,
      reducedMotion: widget.backend.preferences.reducedMotion,
    );
    if (!current()) return;
    if (!found) {
      setState(() => _error = 'Load older replies to find this message.');
      return;
    }
    setState(() => _highlightedMessage = target);
    await Future<void>.delayed(const Duration(milliseconds: 420));
    if (current()) setState(() => _highlightedMessage = null);
  }

  Future<void> _open() async {
    try {
      final session = await widget.backend.openThread(
        widget.roomId,
        widget.rootId,
      );
      if (!mounted) {
        session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _error = null;
      });
      session.addListener(_changed);
      _scheduleRead();
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    }
  }

  void _changed() {
    if (mounted) {
      final anchor = _scroll.hasClients && _scroll.offset > 48
          ? captureTimelineAnchor(_viewportKey, _rowKeys)
          : null;
      setState(() {});
      if (anchor != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && DateTime.now().isAfter(_userInputUntil)) {
            restoreTimelineAnchor(_scroll, _rowKeys, anchor);
          }
        });
      }
      _scheduleRead();
    }
  }

  void _loadNearEdge() {
    if (!_scroll.hasClients || DateTime.now().isAfter(_userInputUntil)) return;
    final session = _session;
    if (session != null &&
        session.canLoadMore &&
        !session.loading &&
        _scroll.position.userScrollDirection == ScrollDirection.reverse &&
        _scroll.offset >= _scroll.position.maxScrollExtent - 240) {
      unawaited(session.loadMore());
    }
  }

  void _scheduleRead() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _acknowledge();
  });

  void _acknowledge() {
    final state = WidgetsBinding.instance.lifecycleState;
    final visible =
        (state == null || state == AppLifecycleState.resumed) &&
        ModalRoute.of(context)?.isCurrent != false;
    _session?.setVisible(visible);
    if (!visible || !_scroll.hasClients || _scroll.offset > 24) {
      return;
    }
    final message = _session?.messages
        .where((m) => !m.pending && !m.failed)
        .firstOrNull;
    if (message != null) unawaited(_session!.markRead(message.id));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleRead();
    } else {
      _session?.setVisible(false);
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final session = _session;
    final value = serializePlainComposer(_draft.document);
    if (session == null ||
        (value.plainText.trim().isEmpty && _attachments.isEmpty)) {
      return;
    }
    final delta = _draft.document.toDelta().toJson();
    final attachments = List<AttachmentDraft>.of(_attachments);
    final editing = _editing, replying = _replying;
    resetRichComposer(_draft);
    setState(() {
      _attachments.clear();
      _editing = null;
      _replying = null;
      _error = null;
    });
    try {
      await widget.backend.submitComposerMessage(
        roomId: widget.roomId,
        text: value.plainText.trim(),
        formattedBody: value.html,
        attachments: attachments,
        editMessageId: editing?.id,
        reply: replying,
        thread: session,
      );
    } catch (error) {
      if (!mounted || error is QueuedSendCancelled) return;
      setState(() {
        final failed = error is PartialComposerSendFailure
            ? null
            : Document.fromJson(delta);
        if (failed != null) {
          _draft.document = restoreFailedComposer(failed, _draft.document);
          _draft.updateSelection(
            TextSelection.collapsed(offset: max(0, _draft.document.length - 1)),
            ChangeSource.local,
          );
        }
        _attachments.insertAll(
          0,
          error is PartialComposerSendFailure ? error.attachments : attachments,
        );
        _editing ??= editing;
        _replying ??= replying;
        _error = safeErrorMessage(error);
      });
    }
  }

  void _queueAttachments(List<AttachmentDraft> drafts) {
    if (!mounted || drafts.isEmpty) return;
    try {
      validateAttachmentSelection(
        [..._attachments, ...drafts].map((d) => d.bytes.length),
      );
      setState(() => _attachments.addAll(drafts));
      _focus.requestFocus();
    } catch (error) {
      setState(() => _error = safeErrorMessage(error));
    }
  }

  Future<void> _attach() async {
    if (_session == null) return;
    try {
      if (kIsWeb) {
        _queueAttachments(await pickBrowserAttachments());
      } else {
        final result = await FilePicker.pickFiles(allowMultiple: true);
        if (result == null) return;
        validateAttachmentSelection(result.files.map((file) => file.size));
        final drafts = <AttachmentDraft>[];
        for (var i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          final bytes = file.bytes ?? await result.xFiles[i].readAsBytes();
          drafts.add(
            AttachmentDraft(
              bytes: bytes,
              name: file.name,
              mimeType:
                  lookupMimeType(file.name, headerBytes: bytes) ??
                  'application/octet-stream',
              spoiler: false,
            ),
          );
        }
        _queueAttachments(drafts);
      }
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    }
  }

  Future<bool> _pasteImage() async {
    try {
      final bytes = await readClipboardImage();
      if (!mounted || bytes == null) return false;
      final mime = lookupMimeType('', headerBytes: bytes) ?? 'image/png';
      _queueAttachments([
        AttachmentDraft(
          bytes: bytes,
          name: 'clipboard-image',
          mimeType: mime,
          spoiler: false,
        ),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _editAttachment(int index) async {
    final draft = _attachments[index];
    final edited = await showAttachmentImageEditor(
      context,
      draft,
      preferences: widget.backend.preferences,
    );
    if (!mounted || edited == null) return;
    final current = _attachments.indexOf(draft);
    if (current >= 0) setState(() => _attachments[current] = edited);
  }

  Future<void> _gif() async {
    final service = GifService();
    try {
      final gif = await showDialog<GifSearchResult>(
        context: context,
        builder: (_) => GiphyDialog(service: service),
      );
      if (gif == null || !mounted) return;
      final bytes = await service.download(gif);
      _queueAttachments([
        AttachmentDraft(
          bytes: bytes,
          name: 'klipy-${DateTime.now().millisecondsSinceEpoch}.gif',
          mimeType: 'image/gif',
          gifSource: gif.shareUrl,
          spoiler: false,
        ),
      ]);
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    } finally {
      service.dispose();
    }
  }

  Future<void> _react(ChatMessage message) async {
    final emoji = await showDialog<EmojiEntry>(
      context: context,
      builder: (_) => EmojiPickerDialog(backend: widget.backend),
    );
    if (emoji == null || !mounted) return;
    await _run(
      () => widget.backend.toggleReaction(
        message.id,
        emoji.emoji,
        customEmoji: emoji.customEmoji?.customEmoji,
      ),
    );
  }

  Future<void> _messageActions(ChatMessage message) async {
    final action = await showModalBottomSheet<MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: MessageActionList(
          message: message,
          actions: messageActionOrder(
            message,
            canEdit: message.attachment == null,
            canPin: widget.backend.canChangeRoomState(
              widget.roomId,
              'm.room.pinned_events',
            ),
          ),
          onAction: (action) => Navigator.pop(sheet, action),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case MessageAction.reply:
        setState(() {
          _replying = message;
          _editing = null;
        });
        _focus.requestFocus();
      case MessageAction.react:
        await _react(message);
      case MessageAction.edit:
        setState(() {
          _editing = message;
          _replying = null;
          _replaceDraft(message.body, message.formattedBody);
        });
        _focus.requestFocus();
      case MessageAction.delete:
        if (!message.own) return;
        final yes = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Delete message?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (yes == true) {
          await _run(() => widget.backend.redactMessage(message.id));
        }
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.body));
      case MessageAction.unread:
        await _run(() => widget.backend.markMessageUnread(message.id));
      case MessageAction.pin:
        await _run(() => widget.backend.toggleMessagePinned(message.id));
      case MessageAction.bookmark:
        await _run(() => widget.backend.toggleMessageBookmarked(message.id));
      case MessageAction.link:
        await Clipboard.setData(
          ClipboardData(
            text: 'https://matrix.to/#/${widget.roomId}/${message.id}',
          ),
        );
      case MessageAction.retry:
        await _run(() => widget.backend.retryMessage(message.id));
      case MessageAction.discard:
        await _run(() => widget.backend.cancelPendingMessage(message.id));
      case MessageAction.thread:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _session?.removeListener(_changed);
    _session?.setVisible(false);
    _session?.dispose();
    _draft.removeListener(_typingChanged);
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ModalRoute.of(context); // Rebuild visibility when another route covers us.
    _scheduleRead();
    final session = _session;
    final messages = session?.messages ?? const <ChatMessage>[];
    final positions = {
      for (final (index, message) in messages.indexed)
        ValueKey('thread-message-${message.id}'): index,
    };
    final receipts = receiptFrontiers(messages);
    final albums = MediaAlbumIndex.fromNewestFirst(messages);
    final participants = messages
        .map((m) => m.senderId)
        .whereType<String>()
        .toSet();
    return Material(
      color: context.deltiecord.panel,
      child: Column(
        children: [
          ListTile(
            title: const Text('Discussion'),
            subtitle: Text(
              '${max(0, messages.length - 1)} loaded replies · ${participants.length} participants',
            ),
            trailing: IconButton(
              tooltip: 'Close discussion',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ),
          const Divider(height: 1),
          if (_error != null || session?.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_error ?? session!.error!),
            ),
          if (session == null)
            Expanded(
              child: Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : TextButton(onPressed: _open, child: const Text('Retry')),
              ),
            )
          else
            Expanded(
              child: ReceiptPlacement(
                messages: messages,
                receiptIds: receipts,
                contentInset: 80,
                hiddenIds: albums.hiddenMessageIds,
                child: Listener(
                  onPointerMove: (_) => _userInputUntil = DateTime.now().add(
                    const Duration(seconds: 1),
                  ),
                  onPointerSignal: (_) => _userInputUntil = DateTime.now().add(
                    const Duration(seconds: 1),
                  ),
                  child: Stack(
                    key: _viewportKey,
                    children: [
                      ListView.builder(
                        controller: _scroll,
                        key: PageStorageKey(
                          'thread:${widget.roomId}:${widget.rootId}',
                        ),
                        reverse: true,
                        itemCount: messages.length + 1,
                        findChildIndexCallback: (key) => positions[key],
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return session.loading
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : session.canLoadMore
                                ? TextButton(
                                    onPressed: session.loadMore,
                                    child: const Text('Load older replies'),
                                  )
                                : const SizedBox.shrink();
                          }
                          final message = messages[index];
                          if (albums.hiddenMessageIds.contains(message.id)) {
                            return const SizedBox.shrink();
                          }
                          final older = index + 1 < messages.length
                              ? messages[index + 1]
                              : null;
                          final newDay =
                              older == null ||
                              !DateUtils.isSameDay(
                                older.timestamp.toLocal(),
                                message.timestamp.toLocal(),
                              );
                          final startsGroup =
                              albums.albums.containsKey(message.id) ||
                              newDay ||
                              older.system ||
                              message.system ||
                              (older.senderId ?? older.sender) !=
                                  (message.senderId ?? message.sender) ||
                              message.timestamp.difference(older.timestamp) >
                                  const Duration(minutes: 7) ||
                              message.reply != null;
                          return GestureDetector(
                            key: ValueKey('thread-message-${message.id}'),
                            onLongPress: () => _messageActions(message),
                            child: KeyedSubtree(
                              key: _rowKeys.putIfAbsent(
                                message.id,
                                GlobalKey.new,
                              ),
                              child: SwipeToReply(
                                messageId: message.id,
                                enabled:
                                    MediaQuery.sizeOf(context).width < 720 &&
                                    !message.pending &&
                                    !message.failed,
                                onReply: () => _reply(message),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (newDay)
                                      MessageDaySeparator(
                                        date: message.timestamp,
                                      ),
                                    Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 32,
                                          ),
                                          child: _MessageRow(
                                            allowThreadNavigation: false,
                                            key: ValueKey(message.id),
                                            message: message,
                                            albumMessages:
                                                albums.albums[message.id],
                                            receiptIds: receipts,
                                            showReceipt: receipts.contains(
                                              message.id,
                                            ),
                                            highlighted:
                                                _highlightedMessage ==
                                                message.id,
                                            startsGroup: startsGroup,
                                            backend: widget.backend,
                                            mediaMessages: messages,
                                            onReply: () => _reply(message),
                                            onEdit:
                                                message.own &&
                                                    message.attachment == null
                                                ? () => setState(() {
                                                    _editing = message;
                                                    _replaceDraft(
                                                      message.body,
                                                      message.formattedBody,
                                                    );
                                                  })
                                                : null,
                                            onDelete:
                                                message.own && message.canRedact
                                                ? () => _run(
                                                    () => widget.backend
                                                        .redactMessage(
                                                          message.id,
                                                        ),
                                                  )
                                                : null,
                                            onReact: () => _react(message),
                                            onRetry: message.failed
                                                ? () => _run(
                                                    () => widget.backend
                                                        .retryMessage(
                                                          message.id,
                                                        ),
                                                  )
                                                : null,
                                            onCancel: message.failed
                                                ? () => _run(
                                                    () => widget.backend
                                                        .cancelPendingMessage(
                                                          message.id,
                                                        ),
                                                  )
                                                : null,
                                            onToggleReaction: (reaction) =>
                                                _run(
                                                  () => widget.backend
                                                      .toggleReaction(
                                                        message.id,
                                                        reaction.key,
                                                        customEmoji: reaction
                                                            .customEmoji,
                                                      ),
                                                ),
                                            onJumpToReply: _jumpToReply,
                                            onShowProfile: (request) =>
                                                showMemberProfile(
                                                  context,
                                                  widget.backend,
                                                  request.$1,
                                                ),
                                            onActionsShown: (_) {},
                                          ),
                                        ),
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: IconButton(
                                            tooltip: 'Message actions',
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () =>
                                                _messageActions(message),
                                            icon: const Icon(
                                              Icons.more_horiz,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: TypingIndicator(names: session.typingNames),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_editing != null)
            ListTile(
              dense: true,
              title: const Text('Editing message'),
              trailing: IconButton(
                tooltip: 'Cancel edit',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _editing = null;
                  resetRichComposer(_draft);
                }),
              ),
            ),
          if (_replying case final reply?)
            ListTile(
              dense: true,
              title: Text('Replying to ${reply.sender}'),
              trailing: IconButton(
                tooltip: 'Cancel reply',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _replying = null),
              ),
            ),
          SafeArea(
            top: false,
            child: VoiceMessageComposer(
              backend: widget.backend,
              roomId: widget.roomId,
              thread: session,
              replyToMessageId: _replying?.id,
              builder: (record) => _MessageComposer(
                key: _composer,
                backend: widget.backend,
                controller: _draft,
                conversationTarget: session?.sendTarget,
                focusNode: _focus,
                roomName: 'Discussion',
                enabled: session != null,
                maxHeight: MediaQuery.sizeOf(context).height * .35,
                sendWithCtrlEnter: widget.backend.preferences.sendWithCtrlEnter,
                onSend: _send,
                onRecord: _editing == null ? record : null,
                onSchedule: _schedule,
                onPoll: _poll,
                onSticker: _sticker,
                onAttach: _attach,
                onGif: _gif,
                onPasteImage: _pasteImage,
                pendingAttachments: _attachments,
                onRemoveAttachment: (index) =>
                    setState(() => _attachments.removeAt(index)),
                onEditAttachment: _editAttachment,
                onToggleAttachmentSpoiler: (index) => setState(() {
                  final old = _attachments[index];
                  _attachments[index] = old.copyWith(spoiler: !old.spoiler);
                }),
                mentionSuggestions: _mentions,
                mentionSelectionIndex: _mentionIndex,
                onMentionSelected: _insertMention,
                onMentionSelectionChanged: (index) =>
                    setState(() => _mentionIndex = index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
