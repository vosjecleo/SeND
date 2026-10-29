// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart' as mx;
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart' as app;

class _Database implements mx.MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends mx.Client {
  _Client() : super('classification-test', database: _Database());
  @override
  String get userID => '@me:test';
  final direct = <String, List<String>>{};
  int accountWrites = 0;
  @override
  Map<String, List<String>> get directChats => direct;
  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> content,
  ) async {
    accountWrites++;
  }
}

void state(
  mx.Room room,
  String type,
  String key,
  Map<String, Object?> content,
) => room.setState(
  mx.Event.fromJson({
    'type': type,
    'state_key': key,
    'content': content,
    'sender': '@me:test',
    'event_id': '\$${room.id}-$type-$key',
    'origin_server_ts': 1,
  }, room),
);

class Fixture {
  final client = _Client();
  late final mx.Room space, channel, forum, dm, group;
  late final MatrixBackend backend;
  Fixture() {
    mx.Room room(String id) {
      final value = mx.Room(
        id: id,
        client: client,
        membership: mx.Membership.join,
      )..partial = false;
      state(value, 'm.room.name', '', {'name': id});
      for (final user in ['@me:test', '@peer:test']) {
        state(value, 'm.room.member', user, {
          'membership': 'join',
          'displayname': user,
        });
      }
      return value;
    }

    space = room('!space:test');
    state(space, 'm.room.create', '', {
      'type': 'm.space',
      'room_version': '11',
    });
    channel = room('!channel:test')
      ..notificationCount = 5
      ..highlightCount = 2;
    forum = room('!forum:test')
      ..notificationCount = 4
      ..highlightCount = 3;
    state(forum, 'net.deltiecord.room.presentation', '', {'kind': 'forum'});
    dm = room('!dm:test')..notificationCount = 1;
    group = room('!group:test');
    for (final child in [channel, forum]) {
      state(space, 'm.space.child', child.id, {
        'via': ['test'],
      });
    }
    client.rooms = [space, channel, forum, dm, group];
    client.direct['@peer:test'] = [dm.id, channel.id, forum.id];
    client.presences['@peer:test'] = mx.CachedPresence(
      mx.PresenceType.online,
      0,
      'Peer status',
      true,
      '@peer:test',
    );
    backend = MatrixBackend(client: client);
  }
  void close() => backend.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'joined server rooms cannot leak into Home through stale m.direct flags',
    () {
      final f = Fixture();
      addTearDown(f.close);
      final before = jsonEncode(f.client.direct);
      expect(f.backend.rooms.map((room) => room.id).toSet(), {
        f.dm.id,
        f.group.id,
      });
      expect(f.backend.directUnreadCount, 1);
      expect(f.backend.serverPingCount, 5);
      expect(f.backend.isRoomDirect(f.channel.id), false);
      expect(f.backend.canMarkRoomDirect(f.channel.id), false);
      expect(jsonEncode(f.client.direct), before);
      expect(f.client.accountWrites, 0);
    },
  );
  test(
    'server summaries never inherit a supposed DM peer status or presence',
    () {
      final f = Fixture();
      addTearDown(f.close);
      f.backend.selectSpace(f.space.id);
      expect(f.backend.rooms.map((room) => room.id).toSet(), {
        f.channel.id,
        f.forum.id,
      });
      for (final room in f.backend.rooms) {
        expect(room.usesChannelIcon, true);
        expect(room.isDirect, false);
        expect(room.directUserId, null);
        expect(room.statusMessage, null);
        expect(room.presence, app.UserPresence.offline);
      }
      expect(
        f.backend.rooms
            .singleWhere((room) => room.id == f.forum.id)
            .presentation,
        app.RoomPresentation.forum,
      );
    },
  );
  test('ordinary DMs keep their peer identity and online status', () {
    final f = Fixture();
    addTearDown(f.close);
    final dm = f.backend.rooms.singleWhere((room) => room.id == f.dm.id);
    expect(dm.isDirect, true);
    expect(dm.directUserId, '@peer:test');
    expect(dm.statusMessage, 'Peer status');
    expect(dm.presence, app.UserPresence.online);
    expect(f.backend.canMarkRoomDirect(dm.id), true);
  });
  test(
    'marking a server channel as a DM is rejected before any account write',
    () async {
      final f = Fixture();
      addTearDown(f.close);
      await expectLater(
        f.backend.setRoomDirect(f.channel.id, true),
        throwsStateError,
      );
      expect(f.client.accountWrites, 0);
      expect(f.client.direct['@peer:test'], contains(f.channel.id));
    },
  );
  test(
    'unlinked and unjoined parents do not hide accessible standalone rooms',
    () {
      final f = Fixture();
      addTearDown(f.close);
      state(f.space, 'm.space.child', f.channel.id, {});
      expect(f.backend.rooms.map((room) => room.id), contains(f.channel.id));
      f.space.membership = mx.Membership.leave;
      expect(f.backend.rooms.map((room) => room.id), contains(f.forum.id));
    },
  );
}
