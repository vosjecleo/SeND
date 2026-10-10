part of 'chat_shell.dart';

class ForumView extends StatefulWidget {
  const ForumView({
    super.key,
    required this.backend,
    required this.room,
    this.onOpenNavigation,
  });
  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback? onOpenNavigation;
  @override
  State<ForumView> createState() => _ForumViewState();
}

class _ForumViewState extends State<ForumView> with WidgetsBindingObserver {
  String _query = '';
  String? _tag;
  bool _oldest = false;
  bool _followingOnly = false;
  bool _unreadOnly = false;
  bool _indexLoading = false;
  String? _indexRequestedFor;
  String? _indexError;
  bool _markingRead = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _acknowledge() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.backend.timelineLoading ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      // Opening the index reads new posts, not replies in unopened threads.
      // Backend foreground/visibility gates still prevent background receipts.
      widget.backend.setConversationAtPresent(true);
      if (!_markingRead &&
          (widget.room.hasUnreadMessages ||
              widget.room.unreadCount > 0 ||
              widget.room.markedUnread)) {
        _markingRead = true;
        unawaited(
          widget.backend
              .markRoomUnread(widget.room.id, false)
              .catchError((_) {})
              .whenComplete(() => _markingRead = false),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _acknowledge();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.backend.setConversationAtPresent(false);
    super.dispose();
  }

  Future<void> _deletePost(ChatMessage post) async {
    if (!post.canRedact) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forum post?'),
        content: const Text(
          'This removes the opening post. Existing replies are not deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.backend.redactMessage(post.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeErrorMessage(error))));
      }
    }
  }

  Future<void> _loadIndex({bool refresh = false, bool older = false}) async {
    if (_indexLoading) return;
    setState(() {
      _indexLoading = true;
      _indexError = null;
    });
    try {
      await widget.backend.loadForumThreads(refresh: refresh);
      if (older && widget.backend.canLoadMoreHistory) {
        await widget.backend.loadMoreHistory();
      }
    } catch (error) {
      if (mounted) setState(() => _indexError = safeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _indexLoading = false);
    }
  }

  Future<void> _create() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _ForumPostEditor(backend: widget.backend, roomId: widget.room.id),
  );

  bool _canEdit(ChatMessage post) =>
      post.own && !post.pending && !post.failed && !post.redacted;

  Future<void> _postActions(ChatMessage post, Offset position) async {
    if (!_canEdit(post) && !post.canRedact) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(position);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (_canEdit(post))
          const PopupMenuItem(value: 'edit', child: Text('Edit post')),
        if (post.canRedact)
          const PopupMenuItem(value: 'delete', child: Text('Delete post')),
      ],
    );
    if (!mounted) return;
    if (action == 'delete') {
      await _deletePost(post);
    } else if (action == 'edit') {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ForumPostEditor(
          backend: widget.backend,
          roomId: widget.room.id,
          original: post,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.backend,
    builder: (context, _) {
      _acknowledge();
      if (_indexRequestedFor != widget.room.id &&
          !widget.backend.timelineLoading) {
        _indexRequestedFor = widget.room.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadIndex(refresh: true);
        });
      }
      final roots = widget.backend.messages
          .where(
            (message) =>
                !message.system &&
                !message.redacted &&
                message.threadRootId == null,
          )
          .toList();
      final tags =
          roots
              .expand((post) => post.forumPost?.tags ?? <String>[])
              .toSet()
              .toList()
            ..sort();
      final posts = roots
          .where(
            (post) =>
                (!_followingOnly ||
                    widget.backend.preferences.followedThreads.contains(
                      post.id,
                    )) &&
                (!_unreadOnly || post.threadUnread) &&
                (_tag == null ||
                    (post.forumPost?.tags.contains(_tag) ?? false)) &&
                (_query.startsWith('#')
                    ? (post.forumPost?.tags ?? const <String>[]).any(
                        (tag) =>
                            tag.toLowerCase().contains(_query.substring(1)),
                      )
                    : '${post.forumPost?.title ?? ''} ${post.body} ${post.sender}'
                          .toLowerCase()
                          .contains(_query)),
          )
          .toList();
      posts.sort(
        (a, b) => _oldest
            ? a.timestamp.compareTo(b.timestamp)
            : (b.threadLatestActivity ?? b.timestamp).compareTo(
                a.threadLatestActivity ?? a.timestamp,
              ),
      );
      return Material(
        color: context.deltiecord.background,
        child: Column(
          children: [
            ListTile(
              leading: widget.onOpenNavigation == null
                  ? const Icon(Icons.forum_outlined)
                  : IconButton(
                      tooltip: 'Rooms',
                      onPressed: widget.onOpenNavigation,
                      icon: const Icon(Icons.menu),
                    ),
              title: Text(widget.room.name),
              subtitle: const Text('Posts and discussions'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Invite to channel',
                    onPressed: () => showInviteMember(
                      context,
                      widget.backend,
                      roomId: widget.room.id,
                    ),
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                  IconButton(
                    tooltip: 'Refresh posts',
                    onPressed: _indexLoading
                        ? null
                        : () => _loadIndex(refresh: true),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'New post',
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search posts or #tags',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                  _tag = null;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Recent activity'),
                    selected: !_oldest,
                    onSelected: (_) => setState(() => _oldest = false),
                  ),
                  ChoiceChip(
                    label: const Text('Oldest'),
                    selected: _oldest,
                    onSelected: (_) => setState(() => _oldest = true),
                  ),
                  FilterChip(
                    label: const Text('Following'),
                    selected: _followingOnly,
                    onSelected: (value) =>
                        setState(() => _followingOnly = value),
                  ),
                  FilterChip(
                    label: const Text('Unread'),
                    selected: _unreadOnly,
                    onSelected: (value) => setState(() => _unreadOnly = value),
                  ),
                  for (final tag in tags.where(
                    (tag) =>
                        _query.startsWith('#') &&
                        tag.toLowerCase().contains(_query.substring(1)),
                  ))
                    FilterChip(
                      label: Text('#$tag'),
                      selected: _tag == tag,
                      onSelected: (selected) =>
                          setState(() => _tag = selected ? tag : null),
                    ),
                ],
              ),
            ),
            if (_indexError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_indexError!),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: posts.length + 1,
                itemBuilder: (context, index) {
                  if (index == posts.length) {
                    return widget.backend.historyLoading || _indexLoading
                        ? const Center(child: CircularProgressIndicator())
                        : widget.backend.canLoadMoreHistory ||
                              widget.backend.canLoadMoreForumThreads
                        ? TextButton(
                            onPressed: () => _loadIndex(older: true),
                            child: const Text('Load older posts'),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              posts.isEmpty
                                  ? 'No posts yet.'
                                  : 'Beginning of forum',
                            ),
                          );
                  }
                  final post = posts[index];
                  final replies = post.threadReplyCount;
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: GestureDetector(
                      onSecondaryTapDown: (details) =>
                          _postActions(post, details.globalPosition),
                      onLongPressStart: (details) =>
                          _postActions(post, details.globalPosition),
                      child: InkWell(
                        onTap: () =>
                            openDiscussion(context, widget.backend, post),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.forumPost?.title ??
                                    post.body.split('\n').first,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                post.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (post.attachment != null)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 180,
                                  ),
                                  child: _AttachmentView(
                                    backend: widget.backend,
                                    messageId: post.id,
                                    attachment: post.attachment!,
                                    gallery: roots,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(post.sender),
                                  Text('$replies replies'),
                                  if (post.threadUnread) const Text('Unread'),
                                  if (_canEdit(post) || post.canRedact)
                                    Builder(
                                      builder: (buttonContext) => IconButton(
                                        tooltip: 'Post actions',
                                        icon: const Icon(Icons.more_horiz),
                                        onPressed: () {
                                          final box =
                                              buttonContext.findRenderObject()
                                                  as RenderBox;
                                          _postActions(
                                            post,
                                            box.localToGlobal(Offset.zero),
                                          );
                                        },
                                      ),
                                    ),
                                  IconButton(
                                    tooltip:
                                        widget
                                            .backend
                                            .preferences
                                            .followedThreads
                                            .contains(post.id)
                                        ? 'Unfollow discussion'
                                        : 'Follow discussion',
                                    icon: Icon(
                                      widget.backend.preferences.followedThreads
                                              .contains(post.id)
                                          ? Icons.bookmark
                                          : Icons.bookmark_border,
                                    ),
                                    onPressed: () async {
                                      final prefs = widget.backend.preferences;
                                      final followed = {
                                        ...prefs.followedThreads,
                                      };
                                      if (!followed.add(post.id)) {
                                        followed.remove(post.id);
                                      }
                                      try {
                                        await widget.backend.updatePreferences(
                                          prefs.copyWith(
                                            followedThreads: followed,
                                          ),
                                        );
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                safeErrorMessage(error),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                  for (final tag
                                      in post.forumPost?.tags ?? <String>[])
                                    Text('#$tag'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ForumPostEditor extends StatefulWidget {
  const _ForumPostEditor({
    required this.backend,
    required this.roomId,
    this.original,
  });
  final ChatBackend backend;
  final String roomId;
  final ChatMessage? original;
  @override
  State<_ForumPostEditor> createState() => _ForumPostEditorState();
}

class _ForumPostEditorState extends State<_ForumPostEditor> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  final _tagFocus = FocusNode();
  final _selectedTags = <String>[];
  String? _error;
  bool _sending = false;
  AttachmentDraft? _cover;
  bool _removeCover = false;

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    if (original == null) return;
    _title.text = original.forumPost?.title ?? original.body.split('\n').first;
    final prefix = '${_title.text}\n\n';
    _body.text = original.body.startsWith(prefix)
        ? original.body.substring(prefix.length)
        : original.body;
    _selectedTags.addAll(original.forumPost?.tags ?? const []);
  }

  void _addTag() {
    final tag = _tags.text.trim();
    if (tag.isEmpty) return;
    if (!_selectedTags.contains(tag) &&
        (_selectedTags.length >= 5 || tag.characters.length > 24)) {
      setState(() => _error = 'Use at most five tags of up to 24 characters.');
      return;
    }
    setState(() {
      if (!_selectedTags.contains(tag)) _selectedTags.add(tag);
      _tags.clear();
      _error = null;
    });
  }

  Future<void> _pickCover() async {
    try {
      if (kIsWeb) {
        final files = await pickBrowserAttachments(accept: 'image/*');
        if (mounted && files.isNotEmpty) setState(() => _cover = files.first);
      } else {
        final result = await FilePicker.pickFiles(type: FileType.image);
        if (result == null) return;
        final file = result.files.single;
        final bytes = file.bytes ?? await result.xFiles.single.readAsBytes();
        if (mounted) {
          setState(
            () => _cover = AttachmentDraft(
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
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    }
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final post = ForumPost.validated(_title.text, [
        ..._selectedTags,
        _tags.text,
      ]);
      if (_body.text.trim().isEmpty) {
        throw const FormatException('Write a post before sending.');
      }
      if (widget.original case final original?) {
        await widget.backend.editForumPost(
          widget.roomId,
          original.id,
          post,
          _body.text,
          cover: _cover,
          removeCover: _removeCover,
        );
      } else {
        await widget.backend.createForumPost(
          widget.roomId,
          post,
          _body.text,
          cover: _cover,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = safeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tags.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: Text(
        widget.original == null ? 'New forum post' : 'Edit forum post',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 120,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: _body,
                minLines: 4,
                maxLines: 10,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Post'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tags,
                focusNode: _tagFocus,
                enabled: !_sending,
                textInputAction: TextInputAction.done,
                onEditingComplete: () {
                  _addTag();
                  _tagFocus.requestFocus();
                },
                decoration: const InputDecoration(
                  labelText: 'Add a tag',
                  helperText: 'Press Enter to add, up to five tags.',
                ),
              ),
              if (_selectedTags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in _selectedTags)
                        InputChip(
                          label: Text(tag),
                          onDeleted: _sending
                              ? null
                              : () => setState(() => _selectedTags.remove(tag)),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _sending ? null : _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  _cover?.name ??
                      (!_removeCover && widget.original?.attachment != null
                          ? 'Change cover image'
                          : 'Add cover image'),
                ),
              ),
              if (_cover != null ||
                  (!_removeCover && widget.original?.attachment != null))
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() {
                          _cover = null;
                          _removeCover = true;
                        }),
                  child: const Text('Remove cover'),
                ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(
            _sending
                ? 'Saving…'
                : widget.original == null
                ? 'Create post'
                : 'Save changes',
          ),
        ),
      ],
    ),
  );
}
