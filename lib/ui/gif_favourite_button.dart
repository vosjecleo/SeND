import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/foundation.dart';
import 'lifecycle_memory_image.dart';
import 'image_zoom_viewer.dart';
import '../services/gif_service.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../models/saved_gif_reference.dart';
import '../services/encoded_image_dimensions.dart';
import 'gif_favourite_star.dart';
import '../services/gif_identity.dart';

SavedGifReference? uploadedGifReference(
  ChatBackend backend,
  ChatMessage message,
) {
  if (message.pending ||
      message.attachment?.sticker == true ||
      message.attachment?.animated != true) {
    return null;
  }
  return SavedGifReference.fromJson({
    'room_id': backend.roomIdForMessage(message.id),
    'event_id': message.id,
    if (backend.roomIdForMessage(message.id) case final roomId?)
      'identity':
          message.attachment?.gifIdentity ?? gifIdentityFor(roomId, message.id),
  });
}

Future<bool> sendSavedGifToRoom(
  BuildContext context,
  ChatBackend backend,
  GifSearchResult gif, {
  required String roomId,
  String? replyToMessageId,
}) async {
  final reference = gif.message;
  if (reference == null) return false;
  final matches = backend.forwardingRooms.where((room) => room.id == roomId);
  if (matches.isEmpty) throw StateError('This conversation is unavailable.');
  final destination = matches.first;
  var allow = destination.encrypted;
  if (!allow && context.mounted) {
    allow =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Send without encryption?'),
            content: Text(
              '${destination.name} is not encrypted. People with access to its history can open this GIF.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Send'),
              ),
            ],
          ),
        ) ==
        true;
  }
  if (!allow || !context.mounted) return false;
  await backend.enqueueRoomSend(
    roomId,
    () => backend.sendSavedGif(
      reference,
      roomId: roomId,
      replyToMessageId: replyToMessageId,
      allowUnencrypted: !destination.encrypted,
    ),
  );
  return true;
}

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

/// Public GIFs keep their URL; uploaded GIFs keep only a source-message reference.
class GifFavouriteGesture extends StatefulWidget {
  const GifFavouriteGesture({
    required this.uri,
    required this.child,
    this.service,
    this.reference,
    this.bytes,
    super.key,
  });
  final Uri? uri;
  final Widget child;

  /// Optional borrowed service for testing. Otherwise owned by this widget.
  final GifService? service;
  final SavedGifReference? reference;
  final Uint8List? bytes;
  @override
  State<GifFavouriteGesture> createState() => _GifFavouriteGestureState();
}

class _GifFavouriteGestureState extends State<GifFavouriteGesture> {
  late final _service = widget.service ?? GifService();
  bool _busy = false;
  bool get _canFavourite {
    if (isFavouriteableGifUri(widget.uri)) return true;
    final bytes = widget.bytes;
    if (widget.reference == null || bytes == null) return false;
    final header = bytes.length >= 6 ? String.fromCharCodes(bytes.take(6)) : '';
    return header == 'GIF87a' ||
        header == 'GIF89a' ||
        hasAnimatedImageHeader(bytes);
  }

  @override
  void dispose() {
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_canFavourite) return widget.child;
    final gif = isFavouriteableGifUri(widget.uri)
        ? GifSearchResult(
            title: 'GIF',
            previewUrl: widget.uri!,
            shareUrl: widget.uri!,
          )
        : GifSearchResult.saved(widget.reference!);
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
          child: Stack(
            children: [
              widget.child,
              Positioned(
                top: 8,
                right: 8,
                child: GifFavouriteStar(gif: gif, service: _service),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final uri = widget.uri;
    if (_busy || !_canFavourite) return;
    setState(() => _busy = true);
    try {
      final size = widget.bytes == null
          ? null
          : await readEncodedImageDimensions(widget.bytes!);
      if (!mounted) return;
      final gif = isFavouriteableGifUri(uri)
          ? GifSearchResult(
              title: 'GIF',
              previewUrl: uri!,
              shareUrl: uri,
              width: size?.width,
              height: size?.height,
            )
          : GifSearchResult.saved(
              widget.reference!,
              width: size?.width,
              height: size?.height,
            );
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
