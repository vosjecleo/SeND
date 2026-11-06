import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/chat_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'support/timeline_segment_fixture.dart';

class _Client extends SegmentClient {
  _Client(super.storage);
  @override
  bool isLogged() => true;
}

void state(Room room, String type, String key, Map<String, Object?> content) =>
    room.setState(
      Event.fromJson({
        'type': type,
        'state_key': key,
        'sender': '@me:test',
        'content': content,
        'event_id': '\$state-$type-$key',
        'origin_server_ts': 1,
      }, room),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final parentOnly in [false, true]) {
    test(
      'notification selects the channel server and DM returns Home, parentOnly=$parentOnly',
      () async {
        final client = _Client(SegmentDatabase());
        final dm = SegmentRoom(client, id: '!dm:test');
        final channel = SegmentRoom(client, id: '!channel:test');
        final space = Room(
          id: '!space:test',
          client: client,
          membership: Membership.join,
        );
        state(space, EventTypes.RoomCreate, '', {
          'type': 'm.space',
          'room_version': '11',
        });
        if (parentOnly) {
          state(channel, 'm.space.parent', space.id, {
            'via': ['test'],
            'canonical': true,
          });
        } else {
          state(space, EventTypes.SpaceChild, channel.id, {
            'via': ['test'],
          });
        }
        client.rooms = [dm, channel, space];
        final backend = MatrixBackend(client: client);
        addTearDown(backend.dispose);
        await backend.selectRoom(dm.id);
        expect(backend.selectedSpaceId, isNull);
        backend.setArchiveOpen(true);
        expect(backend.archiveOpen, true);
        await backend.openAndroidPushTarget(
          NotificationTarget(roomId: channel.id),
        );
        expect(backend.selectedRoom?.id, channel.id);
        expect(backend.selectedSpaceId, space.id);
        // Correct a stale list even when reopening the already-visible room.
        await backend.openAndroidPushTarget(
          NotificationTarget(roomId: channel.id),
        );
        expect(backend.selectedSpaceId, space.id);
        await backend.openAndroidPushTarget(NotificationTarget(roomId: dm.id));
        expect(backend.selectedRoom?.id, dm.id);
        expect(backend.selectedSpaceId, isNull);
        expect(backend.archiveOpen, false);
      },
    );
  }
  test(
    'a joined Space notification opens its channel navigation, not a chat',
    () async {
      final client = _Client(SegmentDatabase());
      final space = Room(
        id: '!space:test',
        client: client,
        membership: Membership.join,
      );
      state(space, EventTypes.RoomCreate, '', {
        'type': 'm.space',
        'room_version': '11',
      });
      client.rooms = [space];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.openAndroidPushTarget(NotificationTarget(roomId: space.id));
      expect(backend.selectedSpaceId, space.id);
      expect(backend.selectedRoom, isNull);
    },
  );
}
