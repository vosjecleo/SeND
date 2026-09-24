import 'package:deltiecord/models/space_administration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'permission editor uses the correct Matrix defaults and nested notification field',
    () {
      final message = administrationRules.singleWhere(
        (rule) => rule.key == 'message',
      );
      final name = administrationRules.singleWhere(
        (rule) => rule.key == 'name',
      );
      final mentions = administrationRules.singleWhere(
        (rule) => rule.key == 'mentions',
      );
      final levels = <String, dynamic>{
        'events_default': 10,
        'state_default': 70,
        'notifications': {'room': 50, 'future': 99},
      };
      expect(message.level(levels), 10);
      expect(name.level(levels), 70);
      expect(mentions.level(levels), 50);
      final updated = mentions.apply(levels, 25);
      expect(updated['notifications'], {'room': 25, 'future': 99});
      expect(levels['notifications'], {'room': 50, 'future': 99});
      expect(message.apply(levels, 20)['events'], {'m.room.message': 20});
    },
  );
  test(
    'role power preserves owner/manual power and combines shared Spaces',
    () {
      const roles = SpaceRoles(
        roles: [SpaceRole(id: 'mod', name: 'Mod', powerLevel: 50)],
        members: {
          '@user': {'mod'},
          '@owner': {'mod'},
        },
      );
      final initial = <String, dynamic>{
        'users': {'@owner': 100, '@manual': 75},
      };
      Map<String, dynamic> apply(
        Map<String, dynamic> current,
        SpaceRoles roles,
        String space,
      ) => applyRolePowerLevels(
        current: current,
        roles: roles,
        spaceId: space,
        actorId: '@owner',
        actorPower: 100,
      );
      final first = apply(initial, roles, '!a');
      expect((first['users'] as Map)['@owner'], 100);
      expect((first['users'] as Map)['@manual'], 75);
      expect((first['users'] as Map)['@user'], 50);
      final second = apply(first, roles, '!b');
      final removedA = apply(second, const SpaceRoles(), '!a');
      expect((removedA['users'] as Map)['@user'], 50);
      final removedB = apply(removedA, const SpaceRoles(), '!b');
      expect((removedB['users'] as Map)['@user'], 0);
      expect((removedB['users'] as Map)['@owner'], 100);
      final manuallyChanged = {
        ...first,
        'users': {...first['users'] as Map, '@user': 80},
      };
      expect(
        (apply(manuallyChanged, const SpaceRoles(), '!a')['users']
            as Map)['@user'],
        80,
      );
      expect(initial['users'], {'@owner': 100, '@manual': 75});
    },
  );
  test('role power rejects escalation without changing input', () {
    const roles = SpaceRoles(
      roles: [SpaceRole(id: 'admin', name: 'Admin', powerLevel: 100)],
      members: {
        '@user': {'admin'},
      },
    );
    final initial = <String, dynamic>{
      'users': {'@actor': 50},
    };
    expect(
      () => applyRolePowerLevels(
        current: initial,
        roles: roles,
        spaceId: '!a',
        actorId: '@actor',
        actorPower: 50,
      ),
      throwsStateError,
    );
    expect(initial['users'], {'@actor': 50});
  });
  test('role display order and privilege order are independent', () {
    const roles = SpaceRoles(
      roles: [
        SpaceRole(
          id: 'friendly',
          name: 'Friend',
          powerLevel: 0,
          color: 0xff112233,
        ),
        SpaceRole(
          id: 'mod',
          name: 'Moderator',
          powerLevel: 50,
          color: 0xffaabbcc,
        ),
      ],
      members: {
        '@user:example.org': {'friendly', 'mod'},
      },
    );
    expect(roles.powerFor('@user:example.org'), 50);
    expect(roles.colorFor('@user:example.org'), 0xff112233);
    expect(roles.powerFor('@other:example.org'), 0);
    expect(roles.equivalentTo(SpaceRoles.fromJson(roles.toJson())), isTrue);
    expect(roles.equivalentTo(const SpaceRoles()), isFalse);
    expect(SpaceRoles.fromJson(roles.toJson()).toJson(), roles.toJson());
  });
  test('rules preserve unrelated permissions and do not mutate input', () {
    final current = <String, dynamic>{
      'users': {'@owner:example.org': 100},
      'events': {'m.room.topic': 75, 'example.custom': 90},
      'ban': 60,
    };
    final packs = administrationRules.singleWhere((r) => r.key == 'packs');
    final changed = packs.apply(current, 40);
    expect((changed['events'] as Map)['example.custom'], 90);
    expect((changed['events'] as Map)['m.room.topic'], 75);
    expect(changed['ban'], 60);
    expect(changed['users'], current['users']);
    expect((current['events'] as Map).containsKey(packs.eventType), isFalse);
    expect(packs.level(changed), 40);
  });
  test(
    'invalid and duplicate role IDs cannot create ambiguous assignments',
    () {
      final roles = SpaceRoles.fromJson({
        'roles': [
          {'id': 'one', 'name': 'One', 'power_level': 10},
          {'id': 'one', 'name': 'Other', 'power_level': 100},
          {'id': 4, 'name': 'Invalid', 'power_level': 100},
        ],
        'members': {
          '@user': ['one', 'missing'],
        },
      });
      expect(roles.roles, hasLength(1));
      expect(roles.powerFor('@user'), 10);
      expect(roles.members['@user'], {'one'});
    },
  );
}
