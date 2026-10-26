import 'package:matrix/matrix.dart';

/// A server notification belongs to its Space, not the latest sender.
/// A standalone group uses its own icon. Only DMs use a sender's picture.
Room? notificationAvatarRoom(Room room) {
  final spaces = room.client.rooms.where((r) => r.isSpace).toList();
  final parents = room.states['m.space.parent']?.values ?? const <Event>[];
  final candidates = spaces
      .where(
        (space) =>
            space.spaceChildren.any((child) => child.roomId == room.id) ||
            parents.any((parent) => parent.stateKey == space.id),
      )
      .toList();
  candidates.sort((a, b) {
    bool canonical(Room space) => parents.any(
      (p) => p.stateKey == space.id && p.content['canonical'] == true,
    );
    final preferred = (canonical(b) ? 1 : 0) - (canonical(a) ? 1 : 0);
    return preferred != 0 ? preferred : a.id.compareTo(b.id);
  });
  return candidates.firstOrNull ?? (room.isDirectChat ? null : room);
}
