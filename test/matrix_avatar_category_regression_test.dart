import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/avatar_media_pool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/matrix_api_lite/generated/fixed_model.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('avatar-test', database: _Database());
  @override
  String get userID => '@me:test';
  final original = Completer<FileResponse>();
  final preview = Completer<FileResponse>();
  final writes = <Map<String, Object?>>[];
  final writeTypes = <String>[];
  final writeTargets = <String>[];
  final childContent = <String, Map<String, Object?>>{};
  final children = <String, List<String>>{};
  final left = <String>[];
  String? failLeave;
  @override
  Future<List<MatrixEvent>> getRoomState(String roomId) async => [
    for (final id in children[roomId] ?? <String>[])
      MatrixEvent.fromJson({
        'type': 'm.space.child',
        'sender': '@me:test',
        'event_id': '\$child',
        'origin_server_ts': 1,
        'state_key': id,
        'content': {
          'via': ['test'],
          ...?childContent[id],
        },
      }),
  ];
  @override
  Future<void> leaveRoom(String roomId, {String? reason}) async {
    if (roomId == failLeave) throw StateError('Offline');
    left.add(roomId);
  }

  Map<String, Object?> permissions = {
    'users': {'@me:test': 100},
    'invite': 0,
    'ban': 50,
    'custom_field': 'keep',
  };
  bool failPermissions = false;
  @override
  Future<Map<String, Object?>> getRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey, {
    Format? format,
  }) async {
    if (failPermissions) throw StateError('Offline');
    return permissions;
  }

  @override
  Future<CachedProfileInformation> getUserProfile(
    String userId, {
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async => CachedProfileInformation.fromProfile(
    ProfileInformation(
      avatarUrl: Uri.parse('mxc://test/avatar'),
      displayname: 'Me',
    ),
    outdated: false,
    updated: DateTime.now(),
  );
  @override
  Future<CachedPresence> fetchCurrentPresence(
    String userId, {
    bool fetchOnlyFromCached = false,
  }) async => throw StateError('No presence');
  @override
  Future<Capabilities> getCapabilities() async =>
      throw StateError('No capabilities');
  @override
  Future<FileResponse> getContentThumbnail(
    String serverName,
    String mediaId,
    int width,
    int height, {
    Method? method,
    bool? allowRemote,
    int? timeoutMs,
    bool? allowRedirect,
    bool? animated,
  }) => preview.future;
  @override
  Future<FileResponse> getContent(
    String serverName,
    String mediaId, {
    bool? allowRemote,
    int? timeoutMs,
    bool? allowRedirect,
  }) => original.future;
  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    writes.add(body);
    writeTypes.add(eventType);
    writeTargets.add('$roomId|$eventType|$stateKey');
    if (eventType == 'm.space.child') childContent[stateKey] = body;
    return '\$saved';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'category ordering follows child order and survives another move and reload',
    () async {
      final client = _Client();
      final space = Room(id: '!space:test', client: client);
      void state(String type, String key, Map<String, Object?> content) {
        space.setState(
          Event.fromJson({
            'type': type,
            'state_key': key,
            'content': content,
            'sender': '@me:test',
            'event_id': '\$event',
            'origin_server_ts': 1,
          }, space),
        );
      }

      state('m.room.create', '', {'type': 'm.space', 'room_version': '11'});
      state('net.deltiecord.space.channels', '', {
        'categories': [
          {'id': 'cat', 'name': 'Text'},
        ],
        'rooms': {'!a:test': 'cat', '!b:test': 'cat', '!c:test': 'cat'},
      });
      client.children[space.id] = ['!a:test', '!b:test', '!c:test'];
      for (final (index, id) in client.children[space.id]!.indexed) {
        final content = <String, Object?>{
          'via': ['remote.test'],
          'suggested': true,
          'custom': 'keep',
          'order': index.toString().padLeft(6, '0'),
        };
        client.childContent[id] = content;
        state('m.space.child', id, content);
      }
      client.rooms = [space];
      final backend = MatrixBackend(client: client)..selectSpace(space.id);
      await backend.moveRoomInSpace(
        '!c:test',
        categoryId: 'cat',
        beforeRoomId: '!a:test',
      );
      expect(backend.selectedSpaceCategories.single.roomIds, [
        '!c:test',
        '!a:test',
        '!b:test',
      ]);
      // The SDK has not received the first move yet.
      await backend.moveRoomInSpace(
        '!b:test',
        categoryId: 'cat',
        beforeRoomId: '!a:test',
      );
      expect(backend.selectedSpaceCategories.single.roomIds, [
        '!c:test',
        '!b:test',
        '!a:test',
      ]);
      expect(client.writeTypes, isNot(contains('m.space.parent')));
      expect(client.writeTypes, isNot(contains('m.room.power_levels')));
      for (var i = 0; i < client.writes.length; i++) {
        final parts = client.writeTargets[i].split('|');
        expect(parts.first, space.id);
        if (client.writeTypes[i] == 'm.space.child') {
          expect(client.writes[i]['via'], ['remote.test']);
          expect(client.writes[i]['suggested'], true);
          expect(client.writes[i]['custom'], 'keep');
        }
        state(client.writeTypes[i], parts.last, client.writes[i]);
      }
      final reloaded = MatrixBackend(client: client)..selectSpace(space.id);
      expect(reloaded.selectedSpaceCategories.single.roomIds, [
        '!c:test',
        '!b:test',
        '!a:test',
      ]);
      reloaded.dispose();
      backend.dispose();
    },
  );
  for (final fail in [false, true]) {
    test('leaving Space includes nested channels, failure=$fail', () async {
      final client = _Client();
      Room makeRoom(String id, bool space) {
        final room = Room(id: id, client: client, membership: Membership.join);
        if (space) {
          room.setState(
            Event.fromJson({
              'type': 'm.room.create',
              'state_key': '',
              'sender': '@me:test',
              'event_id': '\$create',
              'origin_server_ts': 1,
              'content': {'type': 'm.space', 'room_version': '11'},
            }, room),
          );
        }
        return room;
      }

      client.rooms = [
        makeRoom('!root:test', true),
        makeRoom('!nested:test', true),
        makeRoom('!chat:test', false),
        makeRoom('!other:test', false),
      ];
      client.children.addAll({
        '!root:test': ['!nested:test', '!chat:test'],
        '!nested:test': ['!root:test', '!chat:test'],
      });
      final backend = MatrixBackend(client: client);
      if (fail) {
        client.failLeave = '!chat:test';
        await expectLater(backend.leaveRoom('!root:test'), throwsStateError);
        expect(client.left, isEmpty);
      } else {
        await backend.leaveRoom('!root:test');
        expect(client.left, ['!chat:test', '!nested:test', '!root:test']);
      }
      backend.dispose();
    });
  }
  test(
    'explicit layout permission change preserves server permissions',
    () async {
      final client = _Client();
      final room = Room(id: '!space:test', client: client);
      room.setState(
        Event.fromJson({
          'type': 'm.room.create',
          'state_key': '',
          'sender': '@me:test',
          'event_id': '\$create',
          'origin_server_ts': 1,
          'content': {'type': 'm.space', 'room_version': '11'},
        }, room),
      );
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      await backend.setSpaceChannelLayoutPowerLevel(room.id, 50);
      expect(client.writes.single, {
        ...client.permissions,
        'events': {'net.deltiecord.space.channels': 50, 'm.space.child': 50},
      });
      client.failPermissions = true;
      await expectLater(
        backend.setSpaceChannelLayoutPowerLevel(room.id, 25),
        throwsStateError,
      );
      expect(client.writes, hasLength(1));
      backend.dispose();
    },
  );
  for (final scenario in ['lazy', 'denied', 'offline']) {
    test(
      'category permissions with $scenario state never rewrite permissions',
      () async {
        final client = _Client();
        final room = Room(id: '!space:test', client: client);
        room.setState(
          Event.fromJson({
            'type': 'm.room.create',
            'state_key': '',
            'sender': '@me:test',
            'event_id': '\$create',
            'origin_server_ts': 1,
            'content': {'type': 'm.space', 'room_version': '11'},
          }, room),
        );
        client.rooms = [room];
        if (scenario == 'denied') {
          client.permissions = {
            'events': {'m.space.child': 100},
          };
        }
        client.failPermissions = scenario == 'offline';
        final backend = MatrixBackend(client: client);
        backend.selectSpace(room.id);
        if (scenario == 'lazy') {
          await backend.createChannelCategory('Test');
          expect(client.writeTypes, ['net.deltiecord.space.channels']);
        } else {
          await expectLater(
            backend.createChannelCategory('Test'),
            throwsStateError,
          );
          expect(client.writes, isEmpty);
        }
        backend.dispose();
      },
    );
  }
  test('member avatar loads even without a message from that member', () async {
    final directory = await Directory.systemTemp.createTemp(
      'send-member-test-',
    );
    final client = _Client();
    final room = Room(id: '!room:test', client: client)..partial = false;
    room.setState(
      Event.fromJson({
        'type': 'm.room.member',
        'state_key': '@quiet:test',
        'sender': '@quiet:test',
        'content': {
          'membership': 'join',
          'displayname': 'Quiet',
          'avatar_url': 'mxc://test/avatar',
        },
        'event_id': '\$member',
        'origin_server_ts': 1,
      }, room),
    );
    client.rooms = [room];
    final backend = MatrixBackend(
      client: client,
      avatarMediaPool: AvatarMediaPool(directory: directory),
    );
    // The deliberately empty database cannot create a timeline, but room
    // selection and member state remain available, as during initial loading.
    await backend.selectRoom(room.id);
    expect(backend.selectedRoomMembers.single.avatarBytes, isNull);
    client.original.complete(FileResponse(data: Uint8List.fromList([5, 6])));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(backend.selectedRoomMembers.single.avatarBytes, [5, 6]);
    backend.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await directory.delete(recursive: true);
  });
  test(
    'progressive own avatar updates island without reopening profile',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'send-avatar-test-',
      );
      final client = _Client();
      final backend = MatrixBackend(
        client: client,
        avatarMediaPool: AvatarMediaPool(directory: directory),
      );
      await backend.getUserProfile(client.userID);
      expect(backend.profileAvatarBytes, isNull);
      client.preview.complete(FileResponse(data: Uint8List.fromList([1, 2])));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(backend.profileAvatarBytes, [1, 2]);
      client.original.complete(FileResponse(data: Uint8List.fromList([3, 4])));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(backend.profileAvatarBytes, [3, 4]);
      backend.dispose();
      await directory.delete(recursive: true);
    },
  );

  test(
    'real backend preserves existing categories when creating another',
    () async {
      final client = _Client();
      final room = Room(id: '!space:test', client: client);
      for (final state in [
        {
          'type': 'm.room.create',
          'content': {'type': 'm.space', 'creator': '@me:test'},
        },
        {
          'type': 'm.room.power_levels',
          'content': {
            'users': {'@me:test': 100},
            'events': {'net.deltiecord.space.channels': 100},
          },
        },
        {
          'type': 'net.deltiecord.space.channels',
          'content': {
            'categories': [
              {'id': 'existing', 'name': 'Existing'},
            ],
          },
        },
      ]) {
        room.setState(
          Event.fromJson({
            ...state,
            'state_key': '',
            'sender': '@me:test',
            'event_id': '\$old',
            'origin_server_ts': 1,
          }, room),
        );
      }
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      backend.selectSpace(room.id);
      await backend.createChannelCategory('New category');
      expect(backend.selectedSpaceCategories.map((c) => c.name), [
        'Existing',
        'New category',
      ]);
      expect((client.writes.last['categories'] as List).length, 2);
      backend.dispose();
    },
  );
}
