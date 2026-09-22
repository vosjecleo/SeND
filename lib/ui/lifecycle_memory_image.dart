import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// GIF providers also serve looping MP4/WebM renditions.
bool shouldLoopLinkPreview(Uri pageUrl) {
  final host = pageUrl.host.toLowerCase();
  return host == 'giphy.com' ||
      host.endsWith('.giphy.com') ||
      host == 'tenor.com' ||
      host.endsWith('.tenor.com') ||
      pageUrl.path.toLowerCase().endsWith('.gif');
}

/// Owns animated decoding independently of route/UI animation tickers.
/// Callers resolve autoplay and reduced-motion preferences; backgrounding still
/// stops decoding. Only the current frame is retained, never the full animation.
class LifecycleMemoryImage extends StatefulWidget {
  const LifecycleMemoryImage({
    required this.bytes,
    required this.animated,
    required this.autoplay,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    super.key,
  });
  final Uint8List bytes;
  final bool animated;
  final bool autoplay;
  final BoxFit fit;
  final double? width;
  final double? height;
  @override
  State<LifecycleMemoryImage> createState() => _LifecycleMemoryImageState();
}

class _LifecycleMemoryImageState extends State<LifecycleMemoryImage>
    with WidgetsBindingObserver {
  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _timer;
  int _generation = 0;
  bool _foreground = true;
  bool _failed = false;
  bool get _animated =>
      widget.animated ||
      (widget.bytes.length >= 6 &&
          widget.bytes[0] == 0x47 &&
          widget.bytes[1] == 0x49 &&
          widget.bytes[2] == 0x46 &&
          widget.bytes[3] == 0x38);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (_animated) unawaited(_start());
  }

  void _stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _codec?.dispose();
    _codec = null;
  }

  Future<void> _start() async {
    _stop();
    final generation = _generation;
    try {
      final codec = await ui.instantiateImageCodec(widget.bytes);
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      await _advance(generation, codec);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  Future<void> _advance(int generation, ui.Codec codec) async {
    try {
      final next = await codec.getNextFrame();
      if (!mounted || generation != _generation) {
        next.image.dispose();
        return;
      }
      final previous = _frame;
      setState(() {
        _frame = next.image;
        _failed = false;
      });
      // RenderImage still owns the old frame until this rebuild is painted.
      WidgetsBinding.instance.addPostFrameCallback((_) => previous?.dispose());
      if (_foreground && widget.autoplay && codec.frameCount > 1) {
        final duration = next.duration < const Duration(milliseconds: 20)
            ? const Duration(milliseconds: 20)
            : next.duration;
        _timer = Timer(duration, () => unawaited(_advance(generation, codec)));
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant LifecycleMemoryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.autoplay != widget.autoplay ||
        oldWidget.animated != widget.animated) {
      _stop();
      if (_animated) unawaited(_start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stop();
    } else if (_animated) {
      unawaited(_start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stop();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animated) {
      return Image.memory(
        widget.bytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
      );
    }
    if (_failed && _frame == null) {
      return const Icon(Icons.broken_image_outlined);
    }
    return RawImage(
      image: _frame,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
    );
  }
}
