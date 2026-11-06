import 'dart:async';
import 'dart:convert';

import 'package:deltiecord/matrix/space_follow_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('space-follow-tests', database: _Database());
  final joined = <String>[];
  final routes = <String, List<String>?>{};
  final failed = <String>{};
  final push = <String, PushRule>{};
  final roomRules = <PushRule>[];
  final writes = <Map<String, Object?>>[];
  List<Map<String, Object?>> listing = [];
  Completer<void>? joinGate;
  int hierarchyRequests = 0;
  @override
  String get userID => '@me:test';
  @override
  PushRuleSet get globalPushRules =>
      PushRuleSet(override: push.values.toList(), room: roomRules);
  @override
  Future<GetSpaceHierarchyResponse> getSpaceHierarchy(
    String roomId, {
    bool? suggestedOnly,
    int? limit,
    int? maxDepth,
    String? from,
  }) async {
    hierarchyRequests++;
    expect(maxDepth, 1);
    return GetSpaceHierarchyResponse.fromJson({'rooms': listing});
  }

  @override
  Future<String> joinRoom(
    Object? roomIdOrAlias, {
    List<String>? via,
    String? reason,
    ThirdPartySigned? thirdPartySigned,
  }) async {
    final id = '$roomIdOrAlias';
    joined.add(id);
    routes[id] = via;
    await joinGate?.future;
    if (failed.contains(id)) throw StateError('Synthetic join failure');
    final existing = getRoomById(id);
    if (existing == null) {
      rooms.add(_Room(this, id));
    } else {
      existing.membership = Membership.join;
    }
    return id;
  }

  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> body,
  ) async {
    writes.add(Map.of(body));
    accountData[type] = BasicEvent.fromJson({
      'type': type,
      'content': jsonDecode(jsonEncode(body)),
    });
  }

  @override
  Future<void> setPushRule(
    PushRuleKind kind,
    String ruleId,
    List<Object?> actions, {
    String? before,
    String? after,
    List<PushCondition>? conditions,
    String? pattern,
  }) async {
    expect(kind, PushRuleKind.override);
    push[ruleId] = PushRule(
      ruleId: ruleId,
      actions: actions,
      conditions: conditions,
      default$: false,
      enabled: true,
    );
  }

  @override
  Future<void> deletePushRule(PushRuleKind kind, String ruleId) async {
    push.remove(ruleId);
  }
}

class _Room extends Room {
  _Room(Client client, String id, {this.space = false})
    : super(id: id, client: client);
  final bool space;
  final changes = <PushRuleState>[];
  PushRuleState notification = PushRuleState.notify;
  @override
  bool get isSpace => space;
  @override
  PushRuleState get pushRuleState => notification;
  @override
  Future<void> setPushRuleState(PushRuleState value) async {
    changes.add(value);
    notification = value;
  }

  void child(String id) => setState(
    Event.fromJson({
      'type': EventTypes.SpaceChild,
      'state_key': id,
      'event_id': '\$child-$id',
      'sender': '@me:test',
      'origin_server_ts': 1,
      'content': {
        'via': ['test'],
      },
    }, this),
  );
  void recommend(String mode) => setState(
    Event.fromJson({
      'type': 'net.deltiecord.space.pages',
      'state_key': '',
      'event_id': r'$pages',
      'sender': '@me:test',
      'origin_server_ts': 1,
      'content': {'suggested_notifications': mode},
    }, this),
  );
}

Map<String, Object?> channel(
  String id,
  String joinRule, {
  bool space = false,
}) => {
  'room_id': id,
  'name': id,
  'guest_can_join': false,
  'world_readable': false,
  'num_joined_members': 1,
  'join_rule': joinRule,
  'children_state': <Object?>[],
  if (space) 'room_type': 'm.space',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late _Room space;
  late SpaceFollowController controller;
  setUp(() {
    client = _Client();
    space = _Room(client, '!space:test', space: true);
    client.rooms = [space];
    controller = SpaceFollowController(client: client, changed: () {});
  });
  tearDown(() => controller.dispose());

  test(
    'joins accessible channels and invitations, never private or nested spaces',
    () async {
      final invited = _Room(client, '!invited:test')
        ..membership = Membership.invite;
      client.rooms.add(invited);
      client.listing = [
        channel('!public:test', 'public'),
        channel('!members:test', 'restricted'),
        channel(invited.id, 'invite'),
        channel('!private:test', 'invite'),
        channel('!nested:test', 'public', space: true),
      ];
      final result = await controller.joinAvailable(space.id);
      expect(client.joined, ['!public:test', '!members:test', invited.id]);
      expect(result.joined, 3);
      expect(result.failed, 0);
    },
  );
  test(
    'failed joins do not stop the remaining channels and do not loop',
    () async {
      client.listing = [
        channel('!fails:test', 'restricted'),
        channel('!works:test', 'public'),
      ];
      client.failed.add('!fails:test');
      final result = await controller.joinAvailable(space.id);
      expect(result.failed, 1);
      expect(result.joined, 1);
      await controller.joinAvailable(space.id);
      expect(client.joined.where((id) => id == '!fails:test'), hasLength(1));
      await controller.joinAvailable(space.id, force: true);
      expect(client.joined.where((id) => id == '!fails:test'), hasLength(2));
    },
  );
  test(
    'autojoin opt-out is account-scoped and explicit catch-up still works',
    () async {
      client.listing = [channel('!channel:test', 'public')];
      await controller.setAutoJoin(space.id, false);
      expect(controller.autoJoin(space.id), false);
      await controller.joinAvailable(space.id);
      expect(client.joined, isEmpty);
      final restored = SpaceFollowController(client: client, changed: () {});
      addTearDown(restored.dispose);
      expect(restored.autoJoin(space.id), false);
      await restored.joinAvailable(space.id, force: true);
      expect(client.joined, ['!channel:test']);
    },
  );
  test('uses suggested notifications for newly joined channels', () async {
    space.recommend('mentionsOnly');
    client.listing = [channel('!channel:test', 'public')];
    await controller.joinAvailable(space.id);
    expect((client.getRoomById('!channel:test')! as _Room).changes, [
      PushRuleState.mentionsOnly,
    ]);
  });
  test(
    'uses the parent space routing hints when joining a federated channel',
    () async {
      space.child('!remote:elsewhere');
      client.listing = [channel('!remote:elsewhere', 'restricted')];
      await controller.joinAvailable(space.id);
      expect(client.routes['!remote:elsewhere'], ['test']);
    },
  );
  test(
    'enabling automatic joining does not wait for a slow membership request',
    () async {
      await controller.setAutoJoin(space.id, false);
      final gate = Completer<void>();
      client.joinGate = gate;
      client.listing = [channel('!slow:test', 'public')];
      await controller
          .setAutoJoin(space.id, true)
          .timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);
      expect(controller.autoJoin(space.id), true);
      await controller.setMuted(space.id, true);
      expect(controller.muted(space.id), true);
      gate.complete();
      await controller.joinAvailable(space.id);
    },
  );
  test(
    'announcement recommendation takes priority over the general suggestion',
    () async {
      space.setState(
        Event.fromJson({
          'type': 'net.deltiecord.space.pages',
          'state_key': '',
          'event_id': r'$announcement-settings',
          'sender': '@me:test',
          'origin_server_ts': 2,
          'content': {
            'suggested_notifications': 'mentionsOnly',
            'announcement_channel_ids': ['!announcements:test'],
          },
        }, space),
      );
      client.listing = [channel('!announcements:test', 'public')];
      await controller.joinAvailable(space.id);
      expect((client.getRoomById('!announcements:test')! as _Room).changes, [
        PushRuleState.notify,
      ]);
    },
  );
  test(
    'preserves explicit channel preferences and leaves existing members alone',
    () async {
      space.recommend('muted');
      final existing = _Room(client, '!existing:test');
      client.rooms.add(existing);
      client.roomRules.add(
        PushRule(
          ruleId: '!new:test',
          actions: ['notify'],
          default$: false,
          enabled: true,
        ),
      );
      client.listing = [
        channel('!existing:test', 'public'),
        channel('!new:test', 'public'),
      ];
      await controller.joinAvailable(space.id);
      expect(existing.changes, isEmpty);
      expect((client.getRoomById('!new:test')! as _Room).changes, isEmpty);
    },
  );
  test(
    'space mute adds independent child rules and unmute preserves room choices',
    () async {
      space.child('!one:test');
      space.child('!two:test');
      final manual = PushRule(
        ruleId: '!one:test',
        actions: [],
        default$: false,
        enabled: true,
      );
      client.roomRules.add(manual);
      await controller.setMuted(space.id, true);
      expect(controller.roomMuted('!one:test'), true);
      expect(
        client.push.values
            .map((rule) => rule.conditions!.single.pattern)
            .toSet(),
        {'!one:test', '!two:test'},
      );
      expect(client.push.values.every((rule) => rule.actions.isEmpty), true);
      await controller.setMuted(space.id, false);
      expect(client.push, isEmpty);
      expect(client.roomRules.single, same(manual));
      expect(controller.roomMuted('!one:test'), false);
    },
  );
  test(
    'unmuting one of two spaces leaves the other space mute in force',
    () async {
      final second = _Room(client, '!second:test', space: true)
        ..child('!shared:test');
      space.child('!shared:test');
      client.rooms.add(second);
      await controller.setMuted(space.id, true);
      await controller.setMuted(second.id, true);
      expect(client.push, hasLength(2));
      await controller.setMuted(space.id, false);
      expect(client.push, hasLength(1));
      expect(controller.roomMuted('!shared:test'), true);
    },
  );
  test(
    'new channels inherit a mute after sync without changing their own preference',
    () async {
      space.child('!old:test');
      await controller.setAutoJoin(space.id, false);
      await controller.setMuted(space.id, true);
      controller.start();
      space.child('!new:test');
      client.onSync.add(SyncUpdate(nextBatch: 'new-channel'));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(
        client.push.values
            .map((rule) => rule.conditions!.single.pattern)
            .toSet(),
        {'!old:test', '!new:test'},
      );
      expect(client.joined, isEmpty);
    },
  );
  test('leaving a space prevents automatic joins', () async {
    space.membership = Membership.leave;
    client.listing = [channel('!channel:test', 'public')];
    await controller.joinAvailable(space.id);
    expect(client.hierarchyRequests, 0);
    expect(client.joined, isEmpty);
  });
  test(
    'explicitly leaving a channel is respected until an explicit catch-up',
    () async {
      space.child('!channel:test');
      final room = _Room(client, '!channel:test');
      client.rooms.add(room);
      client.listing = [channel(room.id, 'public')];
      await controller.prepareToLeave({room.id});
      room.membership = Membership.leave;
      await controller.joinAvailable(space.id);
      expect(client.joined, isEmpty);
      await controller.joinAvailable(space.id, force: true);
      expect(client.joined, [room.id]);
      expect(
        (client.accountData[spacePreferencesType]!.content[space.id]
            as Map)['excluded_channels'],
        isEmpty,
      );
    },
  );
  test(
    'leaving a server does not let a shared parent auto-rejoin its channels',
    () async {
      final other = _Room(client, '!other:test', space: true)
        ..child('!shared:test');
      space.child('!shared:test');
      final shared = _Room(client, '!shared:test');
      client.rooms.addAll([other, shared]);
      client.listing = [channel(shared.id, 'public')];
      await controller.prepareToLeave({space.id, shared.id});
      shared.membership = Membership.leave;
      await controller.joinAvailable(space.id);
      await controller.joinAvailable(other.id);
      expect(client.joined, isEmpty);
      controller.spaceJoined(space.id);
      await controller.joinAvailable(space.id);
      expect(client.joined, [shared.id]);
    },
  );
  test('manual joining applies a recommendation only once', () async {
    space.recommend('mentionsOnly');
    final room = _Room(client, '!manual:test');
    client.rooms.add(room);
    await controller.channelJoined(space.id, room.id);
    await controller.channelJoined(space.id, room.id);
    expect(room.changes, [PushRuleState.mentionsOnly]);
  });
  test(
    'disposing during a join cannot start another join or change notifications',
    () async {
      final gate = Completer<void>();
      client.joinGate = gate;
      client.listing = [
        channel('!first:test', 'public'),
        channel('!second:test', 'public'),
      ];
      final operation = controller.joinAvailable(space.id);
      await Future<void>.delayed(Duration.zero);
      controller.dispose();
      gate.complete();
      await operation;
      expect(client.joined, ['!first:test']);
      expect((client.getRoomById('!first:test')! as _Room).changes, isEmpty);
    },
  );
}
