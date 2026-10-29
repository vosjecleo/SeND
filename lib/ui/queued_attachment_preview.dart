import 'package:flutter/material.dart';
import '../models/chat_models.dart';

/// Local media stays visibly pending; it is not playable or marked delivered.
class QueuedAttachmentPreview extends StatelessWidget {
  const QueuedAttachmentPreview({required this.draft, super.key});
  final AttachmentDraft draft;
  @override
  Widget build(BuildContext context) {
    final photo = draft.mimeType.startsWith('image/');
    final bytes = photo ? draft.bytes : draft.videoThumbnail;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 260),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: draft.spoiler
            ? const SizedBox(
                width: 260,
                height: 170,
                child: ColoredBox(
                  color: Color(0xff222222),
                  child: Center(child: Icon(Icons.visibility_off_outlined)),
                ),
              )
            : bytes != null
            ? Image.memory(
                bytes,
                fit: BoxFit.contain,
                cacheWidth: 840,
                errorBuilder: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => SizedBox(
    width: 260,
    height: 170,
    child: ColoredBox(
      color: const Color(0xff222222),
      child: Center(
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
      ),
    ),
  );
}

class QueuedSendProgress extends StatelessWidget {
  const QueuedSendProgress({required this.message, super.key});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 4),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.transferStatus ?? 'Sending',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (message.attachment != null) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(value: message.preparationProgress),
          ],
        ],
      ),
    ),
  );
}
