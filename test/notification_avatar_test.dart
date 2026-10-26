import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/services/notification_avatar.dart';

class _Database implements MatrixSdkDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Room extends Room {
  _Room({required super.id, required super.client, this.direct = false});
  final bool direct;
  @override
  bool get isDirectChat => direct;
}

void main() {
  test(
    'server identity wins; standalone groups retain their icon and DMs use sender',
    () {
      final client = Client('test', database: _Database());
      final space = _Room(id: '!space:test', client: client),
          child = _Room(id: '!child:test', client: client);
      final dm = _Room(id: '!dm:test', client: client, direct: true);
      final group = _Room(id: '!group:test', client: client);
      void state(
        Room r,
        String type,
        String key,
        Map<String, Object?> content,
      ) => r.setState(
        Event.fromJson({
          'type': type,
          'state_key': key,
          'content': content,
          'sender': '@me:test',
          'event_id': '\$e',
          'origin_server_ts': 1,
        }, r),
      );
      state(space, 'm.room.create', '', {
        'type': 'm.space',
        'room_version': '11',
      });
      state(space, 'm.space.child', child.id, {
        'via': ['test'],
      });
      client.rooms = [space, child, dm, group];
      expect(notificationAvatarRoom(child), same(space));
      expect(notificationAvatarRoom(dm), isNull);
      expect(notificationAvatarRoom(group), same(group));
    },
  );
}
