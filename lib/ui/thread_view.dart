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
  final _draft = TextEditingController();
  final _scroll = ScrollController();
  ThreadSession? _session;
  String? _error;
  ChatMessage? _editing;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_acknowledge);
    _open();
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
      setState(() {});
      _scheduleRead();
    }
  }

  void _scheduleRead() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _acknowledge();
  });

  void _acknowledge() {
    if (!_scroll.hasClients ||
        _scroll.offset > 24 ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final message = _session?.messages.lastOrNull;
    if (message != null) unawaited(_session!.markRead(message.id));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleRead();
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
    if (session == null || _draft.text.trim().isEmpty) return;
    final value = serializeMarkdownEmojiMessage(_draft.text, const []);
    await _run(() async {
      await session.send(
        value.plainText,
        formattedBody: value.html,
        editMessageId: _editing?.id,
      );
      if (mounted) {
        setState(() {
          _draft.clear();
          _editing = null;
        });
      }
    });
  }

  Future<void> _attach() async {
    final session = _session;
    if (session == null) return;
    await _run(() async {
      final drafts = <AttachmentDraft>[];
      if (kIsWeb) {
        drafts.addAll(await pickBrowserAttachments());
      } else {
        final result = await FilePicker.pickFiles(allowMultiple: true);
        if (result == null) return;
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
      }
      for (final draft in drafts) {
        if (!mounted) return;
        await session.attach(draft);
      }
    });
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
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.add_reaction_outlined),
              title: const Text('React'),
              onTap: () => Navigator.pop(context, 'react'),
            ),
            if (message.own && message.attachment == null)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(context, 'edit'),
              ),
            if (message.canRedact)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete message'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'react':
        await _react(message);
      case 'edit':
        setState(() {
          _editing = message;
          _draft.text = message.body;
        });
      case 'delete':
        await _run(() => widget.backend.redactMessage(message.id));
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.body));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.dispose();
    _session?.removeListener(_changed);
    _session?.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final messages = session?.messages ?? const <ChatMessage>[];
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
              child: ListView.builder(
                controller: _scroll,
                key: PageStorageKey('thread:${widget.roomId}:${widget.rootId}'),
                reverse: true,
                itemCount: messages.length + 1,
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return session.loading
                        ? const Center(child: CircularProgressIndicator())
                        : session.canLoadMore
                        ? TextButton(
                            onPressed: session.loadMore,
                            child: const Text('Load older replies'),
                          )
                        : const SizedBox.shrink();
                  }
                  final message = messages[messages.length - index - 1];
                  return GestureDetector(
                    onLongPress: () => _messageActions(message),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            tooltip: 'Message actions',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _messageActions(message),
                            icon: const Icon(Icons.more_horiz, size: 18),
                          ),
                        ),
                        _MessageRow(
                          allowThreadNavigation: false,
                          key: ValueKey(message.id),
                          message: message,
                          highlighted: false,
                          startsGroup: true,
                          backend: widget.backend,
                          mediaMessages: messages,
                          onReply: () => FocusScope.of(context).nextFocus(),
                          onEdit: message.own && message.attachment == null
                              ? () => setState(() {
                                  _editing = message;
                                  _draft.text = message.body;
                                })
                              : null,
                          onDelete: message.canRedact
                              ? () => _run(
                                  () =>
                                      widget.backend.redactMessage(message.id),
                                )
                              : null,
                          onReact: () => _react(message),
                          onRetry: message.failed
                              ? () => _run(
                                  () => widget.backend.retryMessage(message.id),
                                )
                              : null,
                          onCancel: message.failed
                              ? () => _run(
                                  () => widget.backend.cancelPendingMessage(
                                    message.id,
                                  ),
                                )
                              : null,
                          onToggleReaction: (reaction) => _run(
                            () => widget.backend.toggleReaction(
                              message.id,
                              reaction.key,
                              customEmoji: reaction.customEmoji,
                            ),
                          ),
                          onJumpToReply: (_) {},
                          onShowProfile: (request) => showMemberProfile(
                            context,
                            widget.backend,
                            request.$1,
                          ),
                          onActionsShown: (_) {},
                        ),
                      ],
                    ),
                  );
                },
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
                  _draft.clear();
                }),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach file',
                    onPressed: _sending || session == null ? null : _attach,
                    icon: const Icon(Icons.add),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _draft,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Reply in discussion',
                      ),
                      enabled: session != null && !_sending,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Send reply',
                    onPressed: _sending || session == null ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
