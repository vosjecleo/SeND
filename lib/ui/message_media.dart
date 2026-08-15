part of 'chat_shell.dart';

enum _MediaAction { copyImage, copyReference, save, open, fullscreen }

Future<_MediaAction?> _showMediaContextMenu(
  BuildContext context,
  Offset position, {
  required bool image,
}) {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  return showMenu<_MediaAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (image)
        const PopupMenuItem(
          value: _MediaAction.copyImage,
          child: Text('Copy image'),
        ),
      PopupMenuItem(
        value: _MediaAction.copyReference,
        child: Text(image ? 'Copy image reference' : 'Copy video reference'),
      ),
      PopupMenuItem(
        value: _MediaAction.save,
        child: Text(image ? 'Save image as…' : 'Save video as…'),
      ),
      const PopupMenuItem(
        value: _MediaAction.open,
        child: Text('Open externally'),
      ),
      const PopupMenuItem(
        value: _MediaAction.fullscreen,
        child: Text('View fullscreen'),
      ),
    ],
  );
}

// Inline playback is implemented with media_kit rather than adapted player
// source. Attribution and upstream license details are in CREDITS.md.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview});

  final LinkPreview preview;

  @override
  Widget build(BuildContext context) {
    final video = preview.videoUrl;
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = screen.width * 0.5;
    final maxHeight = screen.height * 0.5;
    final sourceWidth = preview.width?.toDouble() ?? 16;
    final sourceHeight = preview.height?.toDouble() ?? 9;
    final aspectRatio = sourceWidth > 0 && sourceHeight > 0
        ? sourceWidth / sourceHeight
        : 16 / 9;
    final mediaWidth = maxWidth / maxHeight > aspectRatio
        ? maxHeight * aspectRatio
        : maxWidth;
    final mediaHeight = mediaWidth / aspectRatio;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: mediaWidth,
        child: InkWell(
          onTap: () => launchUrl(preview.url),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xff292a30),
              border: Border.all(color: const Color(0xff3b3d46)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (video != null)
                  SizedBox(
                    width: mediaWidth,
                    height: mediaHeight,
                    child: _LinkVideoPlayer(
                      uri: video,
                      thumbnail: preview.imageBytes,
                    ),
                  )
                else if (preview.imageBytes case final image?)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                    ),
                    child: Image.memory(image, fit: BoxFit.contain),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preview.siteName ?? preview.url.host,
                        style: const TextStyle(
                          color: Color(0xffa7a9b4),
                          fontSize: 11,
                        ),
                      ),
                      if (preview.title case final title?) ...[
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xffb8bfff),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (preview.description case final description?) ...[
                        const SizedBox(height: 4),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, height: 1.25),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkVideoPlayer extends StatefulWidget {
  const _LinkVideoPlayer({required this.uri, this.thumbnail});

  final Uri uri;
  final Uint8List? thumbnail;

  @override
  State<_LinkVideoPlayer> createState() => _LinkVideoPlayerState();
}

class _LinkVideoPlayerState extends State<_LinkVideoPlayer> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _opened = false;

  Future<void> _toggle() async {
    if (!_opened) {
      await _player.open(Media(widget.uri.toString()), play: true);
      _opened = true;
    } else {
      await _player.playOrPause();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!_opened)
            if (widget.thumbnail case final thumbnail?)
              Positioned.fill(
                child: Image.memory(thumbnail, fit: BoxFit.cover),
              ),
          if (_opened) Video(controller: _controller),
          if (!_player.state.playing)
            IconButton.filled(
              tooltip: 'Play embedded video',
              onPressed: _toggle,
              icon: const Icon(Icons.play_arrow),
            ),
        ],
      ),
    ),
  );
}

class _AttachmentView extends StatefulWidget {
  const _AttachmentView({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.gallery,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final List<ChatMessage> gallery;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  Future<Uint8List>? _imageBytes;
  bool _revealed = false;
  bool _saving = false;
  bool _opening = false;

  Future<void> _copyReference() async {
    final reference = await widget.backend.getAttachmentReference(
      widget.messageId,
    );
    if (reference == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No safe media reference available')),
        );
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: reference));
  }

  Future<void> _copyImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final bytes = await widget.backend.downloadAttachment(widget.messageId);
    final item = DataWriterItem(suggestedName: widget.attachment.name);
    switch (widget.attachment.mimeType) {
      case 'image/jpeg':
        item.add(Formats.jpeg(bytes));
      case 'image/gif':
        item.add(Formats.gif(bytes));
      case 'image/webp':
        item.add(Formats.webp(bytes));
      default:
        item.add(Formats.png(bytes));
    }
    await clipboard.write([item]);
  }

  Future<void> _showContextMenu(
    Offset position, {
    required bool image,
    VoidCallback? fullscreen,
  }) async {
    final action = await _showMediaContextMenu(context, position, image: image);
    switch (action) {
      case _MediaAction.copyImage:
        await _copyImage();
      case _MediaAction.copyReference:
        await _copyReference();
      case _MediaAction.save:
        await _save();
      case _MediaAction.open:
        await _open();
      case _MediaAction.fullscreen:
        fullscreen?.call();
      case null:
        return;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: widget.attachment.name,
    );
    if (path == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      await File(path).writeAsBytes(bytes, flush: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await widget.backend.downloadAttachment(widget.messageId);
      final directory = await getTemporaryDirectory();
      final name = path.basename(widget.attachment.name);
      final file = File(
        path.join(
          directory.path,
          '${widget.messageId.hashCode}_${name.isEmpty ? 'attachment' : name}',
        ),
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!await launchUrl(Uri.file(file.path))) {
        throw StateError('No application is available to open this file.');
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open attachment: $exception')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showMedia() => showDialog<void>(
    context: context,
    builder: (context) => _MediaLightbox(
      backend: widget.backend,
      messages: widget.gallery,
      initialMessageId: widget.messageId,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.attachment.spoiler && !_revealed) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 208,
          height: 116,
          child: Material(
            color: const Color(0xff17181c),
            borderRadius: BorderRadius.circular(5),
            child: InkWell(
              onTap: () => setState(() => _revealed = true),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility_off_outlined, size: 17),
                    SizedBox(height: 2),
                    Text('Reveal spoiler', style: TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return switch (widget.attachment.kind) {
      AttachmentKind.image => _buildImage(),
      AttachmentKind.video => _InlineVideo(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
        onContextMenu: (position, fullscreen) =>
            _showContextMenu(position, image: false, fullscreen: fullscreen),
        onFullscreen: _showMedia,
      ),
      AttachmentKind.audio => _InlineAudio(
        backend: widget.backend,
        messageId: widget.messageId,
        attachment: widget.attachment,
        onSave: _save,
        onOpen: _open,
      ),
      AttachmentKind.file => _buildFile(),
    };
  }

  Widget _buildImage() {
    _imageBytes ??= widget.backend.downloadAttachment(
      widget.messageId,
      thumbnail: !widget.attachment.animated,
    );
    return FutureBuilder<Uint8List>(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _FileTile(
            attachment: widget.attachment,
            saving: _saving,
            onSave: _save,
            opening: _opening,
            onOpen: _open,
            error: 'Preview unavailable',
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const SizedBox(
            width: 184,
            height: 144,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final screen = MediaQuery.sizeOf(context);
        return Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: screen.width * 0.5,
              maxHeight: screen.height * 0.5,
            ),
            child: InkWell(
              onTap: _showMedia,
              onSecondaryTapDown: (details) => _showContextMenu(
                details.globalPosition,
                image: true,
                fullscreen: _showMedia,
              ),
              child: _PreferenceAwareImage(
                bytes: bytes,
                animated: widget.attachment.animated,
                autoplay: widget.backend.preferences.autoplayGifs,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFile() => _FileTile(
    attachment: widget.attachment,
    saving: _saving,
    onSave: _save,
    opening: _opening,
    onOpen: _open,
  );
}

class _PreferenceAwareImage extends StatelessWidget {
  const _PreferenceAwareImage({
    required this.bytes,
    required this.animated,
    required this.autoplay,
  });

  final Uint8List bytes;
  final bool animated;
  final bool autoplay;

  @override
  Widget build(BuildContext context) {
    if (!animated || autoplay) {
      return Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return _FirstFrameImage(bytes: bytes);
  }
}

class _FirstFrameImage extends StatefulWidget {
  const _FirstFrameImage({required this.bytes});

  final Uint8List bytes;

  @override
  State<_FirstFrameImage> createState() => _FirstFrameImageState();
}

class _FirstFrameImageState extends State<_FirstFrameImage> {
  late Future<ui.Image> _frame = _decode();
  ui.Image? _decoded;

  Future<ui.Image> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    try {
      final frame = await codec.getNextFrame();
      _decoded = frame.image;
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  @override
  void didUpdateWidget(covariant _FirstFrameImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decoded?.dispose();
      _decoded = null;
      _frame = _decode();
    }
  }

  @override
  void dispose() {
    _decoded?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ui.Image>(
    future: _frame,
    builder: (context, snapshot) {
      final image = snapshot.data;
      return image == null
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RawImage(image: image, fit: BoxFit.contain);
    },
  );
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.attachment,
    required this.saving,
    required this.onSave,
    required this.opening,
    required this.onOpen,
    this.error,
  });

  final ChatAttachment attachment;
  final bool saving;
  final VoidCallback onSave;
  final bool opening;
  final VoidCallback onOpen;
  final String? error;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
    decoration: BoxDecoration(
      color: const Color(0xff292a30),
      border: Border.all(color: const Color(0xff3b3d45)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Icon(
          attachment.kind == AttachmentKind.audio
              ? Icons.audio_file_outlined
              : Icons.insert_drive_file_outlined,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(attachment.name, overflow: TextOverflow.ellipsis),
              Text(
                error ?? _fileDetails(attachment),
                style: const TextStyle(fontSize: 11, color: Color(0xff989aa5)),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open attachment',
          onPressed: opening ? null : onOpen,
          icon: opening
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new, size: 18),
        ),
        IconButton(
          tooltip: 'Save attachment',
          onPressed: saving ? null : onSave,
          icon: saving
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download, size: 19),
        ),
      ],
    ),
  );

  String _fileDetails(ChatAttachment attachment) {
    final size = attachment.size;
    if (size == null) return attachment.mimeType;
    final amount = size >= 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(size / 1024).toStringAsFixed(0)} KB';
    return '${attachment.mimeType} · $amount';
  }
}

class _InlineVideo extends StatefulWidget {
  const _InlineVideo({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
    required this.onContextMenu,
    required this.onFullscreen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;
  final void Function(Offset position, VoidCallback fullscreen) onContextMenu;
  final VoidCallback onFullscreen;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _opening = false;
  bool _opened = false;
  String? _error;
  late final Future<Uint8List>? _thumbnail = widget.attachment.hasThumbnail
      ? widget.backend.downloadAttachment(widget.messageId, thumbnail: true)
      : null;

  Future<void> _play() async {
    if (_opening) return;
    if (_opened) {
      await _player.playOrPause();
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) {
        throw StateError('Encrypted streaming is still being prepared.');
      }
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _showFullscreen() {
    widget.onFullscreen();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final maxWidth = screen.width * 0.5;
    final maxHeight = screen.height * 0.5;
    final sourceWidth = widget.attachment.width?.toDouble() ?? 16;
    final sourceHeight = widget.attachment.height?.toDouble() ?? 9;
    final aspectRatio = sourceWidth > 0 && sourceHeight > 0
        ? sourceWidth / sourceHeight
        : 16 / 9;
    final width = maxWidth / maxHeight > aspectRatio
        ? maxHeight * aspectRatio
        : maxWidth;
    final height = width / aspectRatio;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _showFullscreen,
                onSecondaryTapDown: (details) => widget.onContextMenu(
                  details.globalPosition,
                  _showFullscreen,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (!_opened)
                      if (_thumbnail case final thumbnail?)
                        FutureBuilder<Uint8List>(
                          future: thumbnail,
                          builder: (context, snapshot) => snapshot.data == null
                              ? const SizedBox.shrink()
                              : Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                ),
                        ),
                    if (_opened) Video(controller: _controller),
                  ],
                ),
              ),
              if (!_player.state.playing)
                IconButton.filled(
                  tooltip: 'Stream video',
                  onPressed: _opening ? null : _play,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                ),
              if (_error case final error?)
                Positioned(
                  left: 3,
                  right: 3,
                  bottom: 2,
                  child: Text(
                    error,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaLightbox extends StatefulWidget {
  const _MediaLightbox({
    required this.backend,
    required this.messages,
    required this.initialMessageId,
  });

  final ChatBackend backend;
  final List<ChatMessage> messages;
  final String initialMessageId;

  @override
  State<_MediaLightbox> createState() => _MediaLightboxState();
}

class _MediaLightboxState extends State<_MediaLightbox> {
  late int _index = max(
    0,
    widget.messages.indexWhere(
      (message) => message.id == widget.initialMessageId,
    ),
  );
  final Map<String, Future<Uint8List>> _images = {};

  ChatMessage get _message => widget.messages[_index];
  ChatAttachment get _attachment => _message.attachment!;

  void _previous() {
    if (_index + 1 < widget.messages.length) setState(() => _index++);
  }

  void _next() {
    if (_index > 0) setState(() => _index--);
  }

  Future<void> _copyReference() async {
    final reference = await widget.backend.getAttachmentReference(_message.id);
    if (reference != null) {
      await Clipboard.setData(ClipboardData(text: reference));
    }
  }

  Future<void> _copyImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null || _attachment.kind != AttachmentKind.image) return;
    final bytes = await widget.backend.downloadAttachment(_message.id);
    final item = DataWriterItem(suggestedName: _attachment.name);
    switch (_attachment.mimeType) {
      case 'image/jpeg':
        item.add(Formats.jpeg(bytes));
      case 'image/gif':
        item.add(Formats.gif(bytes));
      case 'image/webp':
        item.add(Formats.webp(bytes));
      default:
        item.add(Formats.png(bytes));
    }
    await clipboard.write([item]);
  }

  Future<void> _save() async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Save attachment',
      fileName: _attachment.name,
    );
    if (path == null) return;
    final bytes = await widget.backend.downloadAttachment(_message.id);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> _open() async {
    final bytes = await widget.backend.downloadAttachment(_message.id);
    final directory = await getTemporaryDirectory();
    final safeName = path.basename(_attachment.name);
    final file = File(
      path.join(
        directory.path,
        '${_message.id.hashCode}_${safeName.isEmpty ? 'attachment' : safeName}',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    await launchUrl(Uri.file(file.path));
  }

  Future<void> _contextMenu(Offset position) async {
    final image = _attachment.kind == AttachmentKind.image;
    final action = await _showMediaContextMenu(context, position, image: image);
    switch (action) {
      case _MediaAction.copyImage:
        await _copyImage();
      case _MediaAction.copyReference:
        await _copyReference();
      case _MediaAction.save:
        await _save();
      case _MediaAction.open:
        await _open();
      case _MediaAction.fullscreen || null:
        return;
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
      const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
    },
    child: Focus(
      autofocus: true,
      child: Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) =>
                    _contextMenu(details.globalPosition),
                child: _attachment.kind == AttachmentKind.video
                    ? _LightboxVideo(
                        key: ValueKey(_message.id),
                        backend: widget.backend,
                        messageId: _message.id,
                      )
                    : FutureBuilder<Uint8List>(
                        future: _images.putIfAbsent(
                          _message.id,
                          () => widget.backend.downloadAttachment(_message.id),
                        ),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Text('Image unavailable'),
                            );
                          }
                          if (snapshot.data case final bytes?) {
                            return InteractiveViewer(
                              key: ValueKey(_message.id),
                              minScale: 0.25,
                              maxScale: 8,
                              child: Center(child: Image.memory(bytes)),
                            );
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      ),
              ),
            ),
            if (_index + 1 < widget.messages.length)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: IconButton.filledTonal(
                  tooltip: 'Previous attachment',
                  onPressed: _previous,
                  icon: const Icon(Icons.chevron_left),
                ),
              ),
            if (_index > 0)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: IconButton.filledTonal(
                  tooltip: 'Next attachment',
                  onPressed: _next,
                  icon: const Icon(Icons.chevron_right),
                ),
              ),
            Positioned(
              right: 12,
              top: 12,
              child: Row(
                children: [
                  Text(
                    '${_index + 1}/${widget.messages.length}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Save attachment',
                    onPressed: _save,
                    icon: const Icon(Icons.download),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Open externally',
                    onPressed: _open,
                    icon: const Icon(Icons.open_in_new),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Close viewer',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LightboxVideo extends StatefulWidget {
  const _LightboxVideo({
    required this.backend,
    required this.messageId,
    super.key,
  });

  final ChatBackend backend;
  final String messageId;

  @override
  State<_LightboxVideo> createState() => _LightboxVideoState();
}

class _LightboxVideoState extends State<_LightboxVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Video playback is unavailable.');
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error == null
      ? Video(controller: _controller, fit: BoxFit.contain)
      : Center(child: Text(_error!));
}

class _InlineAudio extends StatefulWidget {
  const _InlineAudio({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    required this.onOpen,
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  State<_InlineAudio> createState() => _InlineAudioState();
}

class _InlineAudioState extends State<_InlineAudio> {
  late final Player _player = Player();
  bool _opening = false;
  bool _opened = false;
  String? _error;

  Future<void> _toggle() async {
    if (_opening) return;
    if (_opened) {
      await _player.playOrPause();
      return;
    }
    setState(() => _opening = true);
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Audio playback is unavailable.');
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: true,
      );
      _opened = true;
    } catch (exception) {
      _error = exception.toString();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 460),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xff292a30),
      border: Border.all(color: const Color(0xff3b3d45)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: StreamBuilder<bool>(
      stream: _player.stream.playing,
      initialData: _player.state.playing,
      builder: (context, snapshot) => Row(
        children: [
          IconButton(
            tooltip: snapshot.data == true ? 'Pause' : 'Play audio',
            onPressed: _toggle,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(snapshot.data == true ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.attachment.name, overflow: TextOverflow.ellipsis),
                if (_error case final error?)
                  Text(
                    error,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open audio externally',
            onPressed: widget.onOpen,
            icon: const Icon(Icons.open_in_new, size: 18),
          ),
          IconButton(
            tooltip: 'Save audio',
            onPressed: widget.onSave,
            icon: const Icon(Icons.download, size: 19),
          ),
        ],
      ),
    ),
  );
}
