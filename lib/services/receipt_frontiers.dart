import '../models/chat_models.dart';

/// Input is newest-first. Each reader contributes one boundary, so group
/// receipts never imply that everyone has read the latest acknowledged event.
Set<String> receiptFrontiers(Iterable<ChatMessage> messages) {
  final result = <String>{};
  final readers = <String>{};
  var sent = false;
  for (final message in messages) {
    if (!message.own ||
        message.system ||
        message.pending ||
        message.failed ||
        message.queued) {
      continue;
    }
    if (!sent) {
      result.add(message.id);
      sent = true;
    }
    for (final reader in message.readBy) {
      if (readers.add(reader.userId)) result.add(message.id);
    }
  }
  return result;
}
