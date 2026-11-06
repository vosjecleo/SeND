/// Sync message references only. Never put attachment keys in account data.
class SavedGifReference {
  const SavedGifReference({
    required this.roomId,
    required this.eventId,
    this.identity,
  });
  final String roomId, eventId;
  final String? identity;
  Uri get uri => Uri(
    scheme: 'matrix-gif',
    path: roomId,
    queryParameters: {'event': eventId},
  );
  Map<String, String> toJson() => {
    'room_id': roomId,
    'event_id': eventId,
    'identity': ?identity,
  };
  static SavedGifReference? fromJson(Object? value) {
    if (value is! Map) return null;
    final room = value['room_id'], event = value['event_id'];
    if (room is! String ||
        event is! String ||
        !room.startsWith('!') ||
        !event.startsWith(r'$') ||
        room.length > 255 ||
        event.length > 255) {
      return null;
    }
    final identity = value['identity'];
    return SavedGifReference(
      roomId: room,
      eventId: event,
      identity:
          identity is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(identity)
          ? identity
          : null,
    );
  }
}
