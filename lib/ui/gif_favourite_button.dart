import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart';
import 'lifecycle_memory_image.dart';
import 'image_zoom_viewer.dart';
import '../services/gif_service.dart';

Future<void> showGifFullscreen(
  BuildContext context,
  Uint8List bytes,
  Uri? source, {
  required bool autoplay,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Positioned.fill(
          child: ImageZoomViewer(
            enableDoubleTap:
                defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS,
            child: Center(
              child: GifFavouriteGesture(
                uri: source,
                child: LifecycleMemoryImage(
                  bytes: bytes,
                  animated: true,
                  autoplay: autoplay,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Close viewer',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);

bool isFavouriteableGifUri(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    (uri.host == 'static.klipy.com' ||
        uri.host == 'giphy.com' ||
        uri.host.endsWith('.giphy.com')) &&
    uri.path.toLowerCase().endsWith('.gif');

/// A favourite stores the public GIF rendition, not a thumbnail or room key.
class GifFavouriteGesture extends StatefulWidget {
  const GifFavouriteGesture({
    required this.uri,
    required this.child,
    this.service,
    super.key,
  });
  final Uri? uri;
  final Widget child;

  /// Optional borrowed service for testing. Otherwise owned by this widget.
  final GifService? service;
  @override
  State<GifFavouriteGesture> createState() => _GifFavouriteGestureState();
}

class _GifFavouriteGestureState extends State<GifFavouriteGesture> {
  late final _service = widget.service ?? GifService();
  bool _busy = false;

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isFavouriteableGifUri(widget.uri)) return widget.child;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Toggle favourite GIF'): _toggle,
      },
      child: Tooltip(
        message: 'Hold to favourite or unfavourite this GIF',
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _busy ? null : _toggle,
          child: widget.child,
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final uri = widget.uri;
    if (_busy || !isFavouriteableGifUri(uri)) return;
    final gif = GifSearchResult(title: 'GIF', previewUrl: uri!, shareUrl: uri);
    setState(() => _busy = true);
    try {
      await _service.favorites();
      await _service.toggleFavorite(gif);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _service.isFavorite(gif)
                  ? 'GIF added to favourites.'
                  : 'GIF removed from favourites.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not save this favourite.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
