/// Keep room-wide aliases out of URLs, escaped text and longer identifiers.
final roomMentionPattern = RegExp(
  r'(?<![A-Za-z0-9_@/\\])@(everyone|room)(?![A-Za-z0-9_:/-]|\.[A-Za-z0-9])',
);
bool containsRoomMention(String text) => roomMentionPattern.hasMatch(text);

bool messageMentionsUser({
  required String body,
  required String userId,
  required String senderId,
  Map<String, Object?>? mentions,
  bool canNotifyRoom = true,
}) {
  if (senderId == userId) return false;
  if (mentions != null) {
    return (mentions['user_ids'] as List? ?? const []).contains(userId) ||
        (mentions['room'] == true && canNotifyRoom);
  }
  // Older Matrix clients may omit m.mentions altogether. Do not use this
  // fallback when the sender supplied an explicit, empty mentions object.
  return (canNotifyRoom && containsRoomMention(body)) ||
      RegExp(
        '${RegExp.escape(userId)}(?![A-Za-z0-9_:/-]|\\.[A-Za-z0-9])',
      ).hasMatch(body);
}
