import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/server_storage.dart';
import 'lifecycle_memory_image.dart';
import 'mobile/mobile_media.dart';

class ServerStorageSelection extends StatefulWidget {
  const ServerStorageSelection({
    required this.backend,
    required this.files,
    required this.selectiveDeletion,
    super.key,
  });
  final ChatBackend backend;
  final List<Map<String, dynamic>> files;
  final bool selectiveDeletion;
  @override
  State<ServerStorageSelection> createState() => _ServerStorageSelectionState();
}

class _ServerStorageSelectionState extends State<ServerStorageSelection> {
  late final _attachments = widget.backend.serverStorageAttachments(
    widget.files,
    isCurrent: () => mounted,
  );
  late final _selected = widget.files
      .map((f) => f['media_id'] as String)
      .toSet();
  Future<void> _confirm() async {
    if (!widget.selectiveDeletion && _selected.length != widget.files.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your homeserver needs an update to delete selected files.',
          ),
        ),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${_selected.length} uploads?'),
        content: const Text(
          "Shared attachments will stop working; messages stay. This can't be undone, and copies elsewhere may remain.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete uploads'),
          ),
        ],
      ),
    );
    if (approved == true && mounted) Navigator.pop(context, _selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.files
        .where((f) => _selected.contains(f['media_id']))
        .fold<num>(0, (sum, file) => sum + (file['bytes'] as num));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files to delete'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              if (_selected.length == widget.files.length) {
                _selected.clear();
              } else {
                _selected.addAll(
                  widget.files.map((f) => f['media_id'] as String),
                );
              }
            }),
            child: Text(
              _selected.length == widget.files.length
                  ? 'Deselect all'
                  : 'Select all',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, size) => GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: (size.maxWidth / 190).floor().clamp(2, 6),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: .9,
                  ),
                  itemCount: widget.files.length,
                  itemBuilder: (context, index) {
                    final file = widget.files[index],
                        id = widget.files[index]['media_id'] as String;
                    return _StorageFile(
                      key: ValueKey(id),
                      backend: widget.backend,
                      file: file,
                      resolve: () async => (await _attachments)[id],
                      selected: _selected.contains(id),
                      onSelect: () => setState(() {
                        if (!_selected.remove(id)) _selected.add(id);
                      }),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_selected.length} selected · ${formatServerStorageBytes(bytes)}',
                    ),
                  ),
                  FilledButton(
                    onPressed: _selected.isEmpty ? null : _confirm,
                    child: const Text('Delete selected'),
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

class _StorageFile extends StatefulWidget {
  const _StorageFile({
    required this.backend,
    required this.file,
    required this.resolve,
    required this.selected,
    required this.onSelect,
    super.key,
  });
  final ChatBackend backend;
  final Map<String, dynamic> file;
  final Future<ChatMessage?> Function() resolve;
  final bool selected;
  final VoidCallback onSelect;
  @override
  State<_StorageFile> createState() => _StorageFileState();
}

class _StorageFileState extends State<_StorageFile> {
  ChatMessage? _resolved;
  late final Future<ChatMessage?> _message = widget.resolve();
  late final _preview = _message.then((message) async {
    if (mounted) setState(() => _resolved = message);
    return message == null
        ? null
        : widget.backend.loadAttachmentPreview(
            message.id,
            isCurrent: () => mounted,
          );
  });
  Future<void> _open() async {
    ChatMessage? message;
    try {
      message = await _message;
    } catch (_) {}
    if (!mounted) return;
    if (message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Preview unavailable. If you know which chat this came from, open the original message and try again.',
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => MobileMediaGallery(
        backend: widget.backend,
        initialMessage: message!,
        isolated: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final video =
        _resolved?.attachment?.kind == AttachmentKind.video ||
        widget.file['kind'] == 'videos' ||
        (widget.file['mimetype'] as String? ?? '').startsWith('video/');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onSelect,
        onLongPress: _open,
        onSecondaryTap: _open,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: FutureBuilder(
                      future: _preview,
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null) {
                          return Center(
                            child: Icon(
                              video
                                  ? (_resolved != null
                                        ? Icons.play_circle_outline
                                        : Icons.videocam_outlined)
                                  : Icons.image_outlined,
                              size: 40,
                            ),
                          );
                        }
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            LifecycleMemoryImage(
                              bytes: bytes,
                              autoplay: false,
                              fit: BoxFit.cover,
                              decodeWidth: 256,
                              animated: false,
                            ),
                            if (video)
                              const Center(
                                child: Icon(
                                  Icons.play_circle_outline,
                                  size: 36,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Checkbox(
                      value: widget.selected,
                      onChanged: (_) => widget.onSelect(),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: 'View file',
                      onPressed: _open,
                      icon: const Icon(Icons.fullscreen),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                formatServerStorageBytes(widget.file['bytes'] as num),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
