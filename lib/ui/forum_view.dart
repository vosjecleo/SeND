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

class _ForumViewState extends State<ForumView> {
  String _query = '';
  String? _tag;
  bool _oldest = false;
  bool _followingOnly = false;
  bool _unreadOnly = false;
  bool _indexLoading = false;
  String? _indexRequestedFor;
  String? _indexError;

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.backend,
    builder: (context, _) {
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
                '${post.forumPost?.title ?? ''} ${post.body} ${post.sender}'
                    .toLowerCase()
                    .contains(_query),
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
                  hintText: 'Search loaded posts',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
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
                  for (final tag in tags)
                    FilterChip(
                      label: Text(tag),
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
                                IconButton(
                                  tooltip:
                                      widget.backend.preferences.followedThreads
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
                                    final followed = {...prefs.followedThreads};
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
  const _ForumPostEditor({required this.backend, required this.roomId});
  final ChatBackend backend;
  final String roomId;
  @override
  State<_ForumPostEditor> createState() => _ForumPostEditorState();
}

class _ForumPostEditorState extends State<_ForumPostEditor> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tags = TextEditingController();
  String? _error;
  bool _sending = false;
  AttachmentDraft? _cover;

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
      final post = ForumPost.validated(_title.text, _tags.text.split(','));
      if (_body.text.trim().isEmpty) {
        throw const FormatException('Write a post before sending.');
      }
      await widget.backend.createForumPost(
        widget.roomId,
        post,
        _body.text,
        cover: _cover,
      );
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_sending,
    child: AlertDialog(
      title: const Text('New forum post'),
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
              TextField(
                controller: _tags,
                enabled: !_sending,
                decoration: const InputDecoration(
                  labelText: 'Tags, separated by commas',
                ),
              ),
              TextButton.icon(
                onPressed: _sending ? null : _pickCover,
                icon: const Icon(Icons.image_outlined),
                label: Text(_cover?.name ?? 'Add cover image'),
              ),
              if (_cover != null)
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() => _cover = null),
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
          child: Text(_sending ? 'Sending…' : 'Create post'),
        ),
      ],
    ),
  );
}
