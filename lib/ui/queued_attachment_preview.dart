import 'dart:math';
import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../services/raw_image.dart';
import '../services/encoded_image_dimensions.dart';
import 'timeline_media_geometry.dart';
import 'deltiecord_theme.dart';

/// Local media stays visibly pending; it is not playable or marked delivered.
class QueuedAttachmentPreview extends StatefulWidget {
  const QueuedAttachmentPreview({
    required this.draft,
    this.mobile = false,
    super.key,
  });
  final AttachmentDraft draft;
  final bool mobile;
  @override
  State<QueuedAttachmentPreview> createState() =>
      _QueuedAttachmentPreviewState();
}

class _QueuedAttachmentPreviewState extends State<QueuedAttachmentPreview> {
  AttachmentDraft get draft => widget.draft;
  late Future<({int width, int height})?> _dimensions = _readDimensions();

  Future<({int width, int height})?> _readDimensions() {
    if (draft.videoWidth case final width? when width > 0) {
      if (draft.videoHeight case final height? when height > 0) {
        return Future.value((width: width, height: height));
      }
    }
    final image =
        draft.mimeType.startsWith('image/') &&
        !isRawImageFile(draft.name, draft.mimeType);
    final bytes = image ? draft.bytes : draft.videoThumbnail;
    return bytes == null
        ? Future.value(null)
        : readEncodedImageDimensions(bytes);
  }

  @override
  void didUpdateWidget(covariant QueuedAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.draft;
    if (!identical(old.bytes, draft.bytes) ||
        !identical(old.videoThumbnail, draft.videoThumbnail) ||
        old.videoWidth != draft.videoWidth ||
        old.videoHeight != draft.videoHeight ||
        old.mimeType != draft.mimeType ||
        old.name != draft.name) {
      _dimensions = _readDimensions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo =
        draft.mimeType.startsWith('image/') &&
        !isRawImageFile(draft.name, draft.mimeType);
    final bytes = photo ? draft.bytes : draft.videoThumbnail;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          widthFactor: 1,
          alignment: Alignment.centerLeft,
          child: FutureBuilder<({int width, int height})?>(
            future: _dimensions,
            builder: (context, snapshot) {
              final screen = MediaQuery.sizeOf(context);
              final video = draft.mimeType.startsWith('video/');
              final size = photo
                  ? timelineImageFrameSize(
                      screen: screen,
                      mobile: widget.mobile,
                      availableWidth: constraints.maxWidth,
                      width: snapshot.data?.width,
                      height: snapshot.data?.height,
                      spoiler: draft.spoiler,
                    )
                  : video
                  ? fitTimelineMediaFrame(
                      maxWidth: min(
                        constraints.maxWidth,
                        widget.mobile
                            ? min(420, max(120, screen.width - 76))
                            : screen.width * .5,
                      ),
                      maxHeight: widget.mobile
                          ? min(520, max(180, screen.height * .52))
                          : screen.height * .5,
                      width: snapshot.data?.width,
                      height: snapshot.data?.height,
                      fallbackAspectRatio: 16 / 9,
                    )
                  : const Size(260, 170);
              return ClipRRect(
                borderRadius: DeltiecordCorners.borderRadius,
                child: SizedBox(
                  key: const ValueKey('queued-attachment-frame'),
                  width: size.width,
                  height: size.height,
                  child: ColoredBox(
                    color: context.deltiecord.elevated,
                    child: draft.spoiler
                        ? const Center(
                            child: Icon(Icons.visibility_off_outlined),
                          )
                        : bytes != null
                        ? Image.memory(
                            bytes,
                            gaplessPlayback: true,
                            fit: BoxFit.contain,
                            cacheWidth: 840,
                            errorBuilder: (_, _, _) => _fallback(),
                          )
                        : _fallback(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fallback() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          draft.mimeType.startsWith('video/')
              ? Icons.videocam_outlined
              : Icons.insert_drive_file_outlined,
        ),
        const SizedBox(height: 8),
        Text(draft.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
