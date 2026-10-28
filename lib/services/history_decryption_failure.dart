class HistoryDecryptionFailure {
  const HistoryDecryptionFailure({
    required this.roomId,
    required this.eventId,
    this.senderId = '',
    this.timestamp = 0,
  });
  final String roomId, eventId, senderId;
  final int timestamp;
  String get key => '$roomId\u0000$eventId';
  Map<String, Object?> toMap() => {
    'room': roomId,
    'event': eventId,
    'sender': senderId,
    'time': timestamp,
  };
  factory HistoryDecryptionFailure.fromMap(Map<String, Object?> data) {
    final room = data['room'],
        event = data['event'],
        sender = data['sender'] ?? '',
        time = data['time'] ?? 0;
    if (room is! String ||
        !room.startsWith('!') ||
        room.length > 512 ||
        event is! String ||
        !event.startsWith(r'$') ||
        event.length > 512 ||
        sender is! String ||
        sender.length > 512 ||
        time is! num ||
        !time.isFinite ||
        time < 0 ||
        time > 8640000000000000) {
      throw const FormatException('Invalid failed-event reference');
    }
    return HistoryDecryptionFailure(
      roomId: room,
      eventId: event,
      senderId: sender,
      timestamp: time.toInt(),
    );
  }
}
