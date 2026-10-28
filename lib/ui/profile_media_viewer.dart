import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'image_zoom_viewer.dart';
import 'lifecycle_memory_image.dart';

Future<void> showProfileMedia(
  BuildContext context,
  Uint8List preview,
  Future<Uint8List?> Function()? loadOriginal,
) => showDialog<void>(
  context: context,
  builder: (context) =>
      _ProfileMediaViewer(preview: preview, loadOriginal: loadOriginal),
);

class _ProfileMediaViewer extends StatefulWidget {
  const _ProfileMediaViewer({required this.preview, this.loadOriginal});
  final Uint8List preview;
  final Future<Uint8List?> Function()? loadOriginal;
  @override
  State<_ProfileMediaViewer> createState() => _ProfileMediaViewerState();
}

class _ProfileMediaViewerState extends State<_ProfileMediaViewer> {
  Uint8List? _original;
  bool _loading = false, _failed = false;
  @override
  void initState() {
    super.initState();
    if (widget.loadOriginal != null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final bytes = await widget.loadOriginal!();
      if (mounted) {
        setState(() {
          _original = bytes;
          _failed = bytes == null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Positioned.fill(
          child: ImageZoomViewer(
            child: Center(
              child: LifecycleMemoryImage(
                bytes: _original ?? widget.preview,
                animated: true,
                autoplay: !MediaQuery.disableAnimationsOf(context),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(),
          ),
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: IconButton.filledTonal(
              tooltip: 'Close viewer',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
        ),
        if (_failed)
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: _load,
                child: const Text('Could not load the original. Retry'),
              ),
            ),
          ),
      ],
    ),
  );
}
