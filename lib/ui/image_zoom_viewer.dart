import 'package:flutter/material.dart';

/// Pinch/pan viewer with a focal-point double-tap toggle. A borrowed controller
/// lets galleries disable page swipes only while the active image is zoomed.
class ImageZoomViewer extends StatefulWidget {
  const ImageZoomViewer({
    required this.child,
    this.transformationController,
    this.minScale = 1,
    this.maxScale = 6,
    this.panEnabled = true,
    this.enableDoubleTap = true,
    super.key,
  });
  final Widget child;
  final TransformationController? transformationController;
  final double minScale, maxScale;
  final bool panEnabled, enableDoubleTap;
  @override
  State<ImageZoomViewer> createState() => _ImageZoomViewerState();
}

class _ImageZoomViewerState extends State<ImageZoomViewer> {
  final _ownedController = TransformationController();
  Offset _tap = Offset.zero;
  TransformationController get _controller =>
      widget.transformationController ?? _ownedController;
  @override
  void dispose() {
    _ownedController.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_controller.value.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
    } else {
      final scale = 2.5.clamp(widget.minScale, widget.maxScale);
      _controller.value = Matrix4.diagonal3Values(scale, scale, 1)
        ..setEntry(0, 3, _tap.dx * (1 - scale))
        ..setEntry(1, 3, _tap.dy * (1 - scale));
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onDoubleTapDown: widget.enableDoubleTap
        ? (details) => _tap = details.localPosition
        : null,
    onDoubleTap: widget.enableDoubleTap ? _toggleZoom : null,
    child: InteractiveViewer(
      transformationController: _controller,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      panEnabled: widget.panEnabled,
      child: widget.child,
    ),
  );
}
