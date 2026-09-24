import '../models/chat_models.dart';

/// Confirmed timestamps come from origin_server_ts. Pending local echoes stay
/// provisional until sync replaces them. Event IDs break equal-time ties.
int compareTimelineMessages(ChatMessage a, ChatMessage b) {
  if (a.pending != b.pending) return a.pending ? -1 : 1;
  final time = b.timestamp.compareTo(a.timestamp);
  return time != 0 ? time : b.id.compareTo(a.id);
}
