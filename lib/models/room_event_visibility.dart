enum CosmeticRoomEvent {
  avatar('Profile pictures'),
  name('Display names'),
  membership('Joins, leaves and invitations'),
  profile('Other profile changes'),
  room('Room name, topic and picture');

  const CosmeticRoomEvent(this.label);
  final String label;
}

/// Personal display preferences, not room permissions. Missing values inherit
/// global defaults. Security/moderation events deliberately have no hide option.
class RoomEventVisibility {
  const RoomEventVisibility({this.defaults = const {}, this.rooms = const {}});
  final Map<String, bool> defaults;
  final Map<String, Map<String, bool>> rooms;

  bool visible(String roomId, CosmeticRoomEvent event) =>
      rooms[roomId]?[event.name] ?? defaults[event.name] ?? true;

  RoomEventVisibility withValue(
    String? roomId,
    CosmeticRoomEvent event,
    bool? value,
  ) {
    final values = Map<String, bool>.of(
      roomId == null ? defaults : rooms[roomId] ?? {},
    );
    if (value == null) {
      values.remove(event.name);
    } else {
      values[event.name] = value;
    }
    if (roomId == null) {
      return RoomEventVisibility(defaults: values, rooms: rooms);
    }
    final next = Map<String, Map<String, bool>>.of(rooms);
    if (values.isEmpty) {
      next.remove(roomId);
    } else {
      next[roomId] = values;
    }
    return RoomEventVisibility(defaults: defaults, rooms: next);
  }

  Map<String, Object?> toJson() => {'defaults': defaults, 'rooms': rooms};

  factory RoomEventVisibility.fromJson(Object? json) {
    Map<String, bool> flags(Object? value) => value is Map
        ? {
            for (final entry in value.entries)
              if (entry.key is String && entry.value is bool)
                entry.key as String: entry.value as bool,
          }
        : {};
    if (json is! Map) return const RoomEventVisibility();
    final rooms = json['rooms'];
    return RoomEventVisibility(
      defaults: flags(json['defaults']),
      rooms: rooms is Map
          ? {
              for (final entry in rooms.entries)
                if (entry.key is String && entry.value is Map)
                  entry.key as String: flags(entry.value),
            }
          : {},
    );
  }
}
