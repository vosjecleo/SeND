import 'package:flutter/foundation.dart';

import '../models/chat_models.dart';

/// A bounded, disposable view of a standard Matrix thread. Closing it must
/// release its sync subscriptions; it never changes the main room selection.
abstract class ThreadSession extends ChangeNotifier {
  String get roomId;
  String get rootId;
  List<ChatMessage> get messages;
  bool get loading;
  bool get canLoadMore;
  String? get error;
  Future<void> loadMore();
  Future<void> send(
    String text, {
    String? formattedBody,
    String? editMessageId,
  });
  Future<void> attach(AttachmentDraft attachment);
  Future<void> markRead(String eventId) async {}
}
