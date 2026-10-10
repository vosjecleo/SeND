import '../models/chat_models.dart';

/// Presentation only. The original events stay in the timeline, and reappear
/// when a later key download decrypts them. Never collapse a plaintext message
/// merely because its body looks like an error.
List<ChatMessage> collapseUnavailableHistory(
  List<ChatMessage> messages,
  Set<String> unavailableIds,
) {
  var count = 0;
  while (count < messages.length &&
      unavailableIds.contains(messages[count].id)) {
    count++;
  }
  if (count < 2) return messages;
  final first = messages.first;
  return [
    ChatMessage(
      id: first.id,
      sender: '',
      body:
          '$count earlier messages could not be decrypted. '
          'They will appear if their keys become available.',
      timestamp: first.timestamp,
      pending: false,
      system: true,
    ),
    ...messages.skip(count),
  ];
}
