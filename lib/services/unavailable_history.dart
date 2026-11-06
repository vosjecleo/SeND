import '../models/chat_models.dart';

/// Presentation only. The original events stay in the timeline, and reappear
/// when a later key download decrypts them. Never collapse a plaintext message
/// merely because its body looks like an error.
List<ChatMessage> collapseUnavailableHistory(
  List<ChatMessage> messages,
  Set<String> unavailableIds,
) {
  final result = <ChatMessage>[];
  for (var i = 0; i < messages.length;) {
    final start = i;
    while (i < messages.length && unavailableIds.contains(messages[i].id)) {
      i++;
    }
    final count = i - start;
    if (count < 2) {
      result.add(messages[start]);
      if (count == 0) i++;
      continue;
    }
    final first = messages[start];
    result.add(
      ChatMessage(
        id: first.id,
        sender: '',
        body:
            'Can\'t read $count earlier messages without their encryption keys.',
        timestamp: first.timestamp,
        pending: false,
        system: true,
      ),
    );
  }
  return result.length == messages.length ? messages : result;
}
