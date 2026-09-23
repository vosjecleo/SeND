import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'lifecycle_memory_image.dart';
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
          child: InteractiveViewer(
            child: Center(
              child: LifecycleMemoryImage(
                bytes: bytes,
                animated: true,
                autoplay: autoplay,
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
                if (isFavouriteableGifUri(source))
                  GifFavouriteButton(uri: source!),
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
class GifFavouriteButton extends StatefulWidget {
  const GifFavouriteButton({required this.uri, super.key});
  final Uri uri;
  @override
  State<GifFavouriteButton> createState() => _GifFavouriteButtonState();
}

class _GifFavouriteButtonState extends State<GifFavouriteButton> {
  final _service = GifService();
  bool _busy = false;
  GifSearchResult get _gif => GifSearchResult(
    title: 'GIF',
    previewUrl: widget.uri,
    shareUrl: widget.uri,
  );
  @override
  void initState() {
    super.initState();
    _service.favorites().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: _service.isFavorite(_gif)
        ? 'Remove favourite GIF'
        : 'Favourite GIF',
    icon: Icon(_service.isFavorite(_gif) ? Icons.star : Icons.star_border),
    onPressed: _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await _service.toggleFavorite(_gif);
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(
                    content: Text('Could not save this favourite.'),
                  ),
                );
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
  );
}
