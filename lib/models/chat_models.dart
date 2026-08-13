enum SessionStatus { starting, signedOut, signingIn, signedIn, failed }

class RoomSummary {
  const RoomSummary({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.unreadCount,
  });

  final String id;
  final String name;
  final String lastMessage;
  final int unreadCount;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.timestamp,
    required this.pending,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime timestamp;
  final bool pending;
}
