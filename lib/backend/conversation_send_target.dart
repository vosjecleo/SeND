import '../models/chat_models.dart';

typedef ConversationTextSend =
    Future<void> Function(
      String text, {
      String? formattedBody,
      String? editMessageId,
      String? replyToMessageId,
    });
typedef ConversationAttachmentSend =
    Future<void> Function(AttachmentDraft draft, {String? replyToMessageId});

/// Immutable routing, separate from a view's loading/scroll lifecycle. Queued
/// sends can outlive a closed view, but never a signed-out account session.
final class ConversationSendTarget {
  const ConversationSendTarget({
    required this.roomId,
    this.threadRootId,
    required this.send,
    required this.attach,
    this.sticker,
  });
  final String roomId;
  final String? threadRootId;
  final ConversationTextSend send;
  final ConversationAttachmentSend attach;
  final Future<void> Function(StickerSummary)? sticker;
}
