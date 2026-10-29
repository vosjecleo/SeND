import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';
import 'conversation_send_target.dart';

/// A bounded, disposable view of a standard Matrix thread. Closing it must
/// release its sync subscriptions; it never changes the main room selection.
abstract class ThreadSession extends ChangeNotifier {
  String get roomId;
  String get rootId;
  bool get visible => false;
  void setVisible(bool visible) {}
  ConversationSendTarget get sendTarget => ConversationSendTarget(
    roomId: roomId,
    threadRootId: rootId,
    send: send,
    attach: attach,
  );

  /// Newest first, matching the main timeline and its reversed scroll view.
  List<ChatMessage> get messages;
  bool get loading;
  bool get canLoadMore;
  String? get error;
  Future<void> loadMore();
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
    String? replyToMessageId,
  });
  Future<void> attach(AttachmentDraft attachment, {String? replyToMessageId});
  Future<void> markRead(String eventId) async {}
  List<String> get typingNames => const [];
  Future<void> setTyping(bool typing) async {}
  Future<void> sendSticker(StickerSummary sticker) async =>
      throw UnsupportedError('Stickers are unavailable.');
  Future<void> sendPoll(PollDraft poll) async =>
      throw UnsupportedError('Polls are unavailable.');
  Future<void> schedule(
    String text,
    DateTime at, {
    String? replyToMessageId,
  }) async => throw UnsupportedError('Scheduled messages are unavailable.');
}
