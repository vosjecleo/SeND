import 'package:html/parser.dart' as html_parser;

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
    final recipients = mentions['user_ids'];
    return (recipients is List && recipients.contains(userId)) ||
        (mentions['room'] == true && canNotifyRoom);
  }
  // Older Matrix clients may omit m.mentions altogether. Do not use this
  // fallback when the sender supplied an explicit, empty mentions object.
  return (canNotifyRoom && containsRoomMention(body)) ||
      RegExp(
        '${RegExp.escape(userId)}(?![A-Za-z0-9_:/-]|\\.[A-Za-z0-9])',
      ).hasMatch(body);
}

/// Visual mention styling also applies to the sender's own messages. It must
/// not create self-notifications or change unread/notification policy.
bool messageHasVisualMention({
  required String body,
  Map<String, Object?>? mentions,
  String? formattedBody,
  bool isReply = false,
}) {
  final users = mentions?['user_ids'];
  // Reply recipient metadata is not an authored mention. The actual recipient
  // gets their reply highlight through pingedCurrentUser instead.
  return (!isReply && users is List && users.whereType<String>().isNotEmpty) ||
      mentions?['room'] == true ||
      containsRoomMention(body) ||
      RegExp(
        r'(?<![A-Za-z0-9_@/\\])@[A-Za-z0-9._=/-]+:[A-Za-z0-9][A-Za-z0-9.:-]*',
      ).hasMatch(body) ||
      _hasFormattedUserMention(formattedBody);
}

bool _hasFormattedUserMention(String? html) {
  if (html == null) return false;
  final fragment = html_parser.parseFragment(html);
  for (final reply in fragment.querySelectorAll('mx-reply')) {
    reply.remove();
  }
  for (final link in RegExp(
    r'''href\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).allMatches(fragment.outerHtml)) {
    final uri = Uri.tryParse(link.group(1)!);
    if (uri?.host != 'matrix.to' || !{'https', 'http'}.contains(uri?.scheme)) {
      continue;
    }
    try {
      if (RegExp(
        r'^/(?:user/)?@[^:/\s]+:[^/\s]+$',
      ).hasMatch(Uri.decodeComponent(uri!.fragment))) {
        return true;
      }
    } on FormatException {
      continue;
    }
  }
  return false;
}
