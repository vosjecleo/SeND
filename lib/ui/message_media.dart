part of 'chat_shell.dart';

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
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;

  @override
  State<_AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<_AttachmentView> {
  Future<Uint8List>? _imageBytes;
  bool _revealed = false;
  bool _saving = false;
  bool _opening = false;

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

  void _showImage() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<Uint8List>(
                future: widget.backend.downloadAttachment(widget.messageId),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Image unavailable'));
                  }
                  if (snapshot.data case final bytes?) {
                    return InteractiveViewer(
                      minScale: 0.25,
                      maxScale: 8,
                      child: Center(child: Image.memory(bytes)),
                    );
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: IconButton.filledTonal(
                tooltip: 'Close image',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              onTap: _showImage,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
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
  });

  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  final VoidCallback onOpen;

  @override
  State<_InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<_InlineVideo> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  bool _opening = false;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    if (_opening || _opened) return;
    setState(() => _opening = true);
    try {
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) return;
      await _player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
        play: false,
      );
      _opened = true;
    } catch (exception) {
      _error = exception.toString();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

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
    showDialog<void>(
      context: context,
      builder: (context) => _FullscreenVideo(
        backend: widget.backend,
        messageId: widget.messageId,
      ),
    );
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
                child: Video(controller: _controller),
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
              Positioned(
                right: 0,
                top: 0,
                child: SizedBox.square(
                  dimension: 24,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: 'Video options',
                    onSelected: (value) =>
                        value == 'open' ? widget.onOpen() : widget.onSave(),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'open',
                        child: Text('Open externally'),
                      ),
                      PopupMenuItem(value: 'save', child: Text('Save video')),
                    ],
                  ),
                ),
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

class _FullscreenVideo extends StatefulWidget {
  const _FullscreenVideo({required this.backend, required this.messageId});

  final ChatBackend backend;
  final String messageId;

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
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
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Positioned.fill(
          child: _error == null
              ? Video(controller: _controller, fit: BoxFit.contain)
              : Center(child: Text(_error!)),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: IconButton.filledTonal(
            tooltip: 'Close video',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    ),
  );
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
