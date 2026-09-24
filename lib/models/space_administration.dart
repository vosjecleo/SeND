import 'dart:math' as math;

const spaceRolesEventType = 'net.deltiecord.space.roles';

/// Compute a single atomic power-level event, retaining manual power and
/// contributions from other Spaces sharing a child room. Any authority error
/// rejects the entire calculation before the caller makes a network write.
Map<String, dynamic> applyRolePowerLevels({
  required Map<String, dynamic> current,
  required SpaceRoles roles,
  required String spaceId,
  required String actorId,
  required int actorPower,
}) {
  const key = 'net.deltiecord.role_power';
  final users = Map<String, dynamic>.from(current['users'] as Map? ?? {});
  final previous = Map<String, dynamic>.from(current[key] as Map? ?? {});
  final tracking = Map<String, dynamic>.of(previous);
  for (final userId in {...roles.members.keys, ...previous.keys}) {
    final old = previous[userId] is Map ? previous[userId] as Map : const {};
    final existing = users[userId] is int
        ? users[userId] as int
        : current['users_default'] as int? ?? 0;
    final baseline = old['applied'] == existing && old['baseline'] is int
        ? old['baseline'] as int
        : existing;
    final sources = <String, int>{
      if (old['spaces'] is Map)
        for (final entry in (old['spaces'] as Map).entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
    };
    final rolePower = roles.powerFor(userId);
    if (rolePower > 0) {
      sources[spaceId] = rolePower;
    } else {
      sources.remove(spaceId);
    }
    final desired = sources.values.fold(baseline, math.max);
    if (desired != existing &&
        (userId == actorId || existing >= actorPower || desired > actorPower)) {
      throw StateError('Cannot change $userId at your power level.');
    }
    users[userId] = desired;
    tracking[userId] = {
      'baseline': baseline,
      'applied': desired,
      'spaces': sources,
    };
  }
  return {...current, 'users': users, key: tracking};
}

class SpaceRole {
  const SpaceRole({
    required this.id,
    required this.name,
    required this.powerLevel,
    this.color,
  });
  final String id;
  final String name;
  final int powerLevel;
  final int? color;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'power_level': powerLevel,
    'color': color,
  };
}

class SpaceRoles {
  const SpaceRoles({this.roles = const [], this.members = const {}});

  /// Highest displayed role is first; permissions use the highest level, not
  /// the display order. IDs survive renames and moves.
  final List<SpaceRole> roles;
  final Map<String, Set<String>> members;
  bool equivalentTo(SpaceRoles other) {
    if (roles.length != other.roles.length ||
        members.length != other.members.length) {
      return false;
    }
    for (var i = 0; i < roles.length; i++) {
      final a = roles[i], b = other.roles[i];
      if (a.id != b.id ||
          a.name != b.name ||
          a.powerLevel != b.powerLevel ||
          a.color != b.color) {
        return false;
      }
    }
    return members.entries.every(
      (entry) =>
          other.members[entry.key]?.length == entry.value.length &&
          entry.value.containsAll(other.members[entry.key]!),
    );
  }

  List<SpaceRole> forUser(String userId) =>
      roles.where((r) => members[userId]?.contains(r.id) == true).toList();
  int powerFor(String userId) => forUser(
    userId,
  ).fold(0, (level, role) => math.max(level, role.powerLevel));
  int? colorFor(String userId) =>
      forUser(userId).where((r) => r.color != null).firstOrNull?.color;
  Map<String, Object?> toJson() => {
    'version': 1,
    'roles': roles.map((r) => r.toJson()).toList(),
    'members': {
      for (final entry in members.entries) entry.key: entry.value.toList(),
    },
  };
  factory SpaceRoles.fromJson(Map<String, dynamic>? json) {
    final roles = <SpaceRole>[];
    final seen = <String>{};
    if (json?['roles'] case final List raw) {
      for (final item in raw.whereType<Map>()) {
        final id = item['id'];
        final name = item['name'];
        final power = item['power_level'];
        if (id is! String ||
            id.isEmpty ||
            name is! String ||
            power is! int ||
            !seen.add(id)) {
          continue;
        }
        roles.add(
          SpaceRole(
            id: id,
            name: name,
            powerLevel: power,
            color: item['color'] is int ? item['color'] as int : null,
          ),
        );
      }
    }
    final assignments = json?['members'];
    return SpaceRoles(
      roles: roles,
      members: assignments is Map
          ? {
              for (final entry in assignments.entries)
                if (entry.key is String && entry.value is List)
                  entry.key as String: (entry.value as List)
                      .whereType<String>()
                      .where(seen.contains)
                      .toSet(),
            }
          : {},
    );
  }
}

/// A single concrete Matrix permission can cover multiple product actions.
/// Never represent independent toggles which the server cannot enforce.
class AdministrationRule {
  const AdministrationRule(
    this.key,
    this.label, {
    this.eventType,
    this.fallback = 50,
    this.stateEvent = true,
    this.notification = false,
  });
  final String key;
  final String label;
  final String? eventType;
  final int fallback;
  final bool stateEvent;
  final bool notification;
  int level(Map<String, dynamic> content) {
    if (notification) {
      final notifications = content['notifications'];
      return notifications is Map && notifications['room'] is int
          ? notifications['room'] as int
          : fallback;
    }
    final events = content['events'];
    final value = eventType == null
        ? content[key]
        : events is Map
        ? events[eventType]
        : null;
    if (value is int) return value;
    // The channel manager also has a conservative local fallback until a
    // Space explicitly configures its namespaced layout permission.
    if (key == 'categories') return fallback;
    final defaultKey = stateEvent ? 'state_default' : 'events_default';
    if (eventType != null && content[defaultKey] is int) {
      return content[defaultKey] as int;
    }
    return fallback;
  }

  Map<String, dynamic> apply(Map<String, dynamic> content, int level) {
    final next = Map<String, dynamic>.of(content);
    if (notification) {
      next['notifications'] = {
        ...?content['notifications'] as Map?,
        'room': level,
      };
    } else if (eventType == null) {
      next[key] = level;
    } else {
      next['events'] = {...?content['events'] as Map?, eventType!: level};
    }
    return next;
  }
}

const administrationRules = [
  AdministrationRule(
    'voice_membership',
    'Join/leave voice sessions',
    eventType: 'com.famedly.call.member',
  ),
  AdministrationRule(
    'voice_notification',
    'Ring a voice/video call',
    eventType: 'org.matrix.msc4075.rtc.notification',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule('users_default', 'Default member power', fallback: 0),
  AdministrationRule(
    'message',
    'Send/edit messages, attachments and forum posts',
    eventType: 'm.room.message',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule(
    'encrypted',
    'Send encrypted events',
    eventType: 'm.room.encrypted',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule(
    'stickers',
    'Send stickers',
    eventType: 'm.sticker',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule(
    'reactions',
    'React to messages',
    eventType: 'm.reaction',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule(
    'polls',
    'Create polls',
    eventType: 'org.matrix.msc3381.poll.start',
    stateEvent: false,
    fallback: 0,
  ),
  AdministrationRule(
    'mentions',
    'Notify everyone in the room',
    notification: true,
  ),
  AdministrationRule(
    'encryption',
    'Enable/change encryption state',
    eventType: 'm.room.encryption',
  ),
  AdministrationRule(
    'aliases',
    'Set published room aliases',
    eventType: 'm.room.canonical_alias',
  ),
  AdministrationRule(
    'presentation',
    'Change text/voice/forum presentation',
    eventType: 'net.deltiecord.room.presentation',
  ),
  AdministrationRule(
    'timeouts',
    'Record timed moderation actions',
    eventType: 'net.deltiecord.room.timeouts',
  ),
  AdministrationRule(
    'tombstone',
    'Publish a room upgrade/replacement',
    eventType: 'm.room.tombstone',
  ),
  AdministrationRule(
    'parent',
    'Link parent spaces',
    eventType: 'm.space.parent',
  ),
  AdministrationRule(
    'events_default',
    'Send messages and thread/forum replies',
    fallback: 0,
  ),
  AdministrationRule('invite', 'Invite members', fallback: 0),
  AdministrationRule('kick', 'Remove members'),
  AdministrationRule('ban', 'Ban members'),
  AdministrationRule('redact', 'Remove other members’ messages'),
  AdministrationRule('state_default', 'Other room settings'),
  AdministrationRule(
    'power',
    'Edit permissions and member power',
    eventType: 'm.room.power_levels',
    fallback: 100,
  ),
  AdministrationRule('name', 'Change room name', eventType: 'm.room.name'),
  AdministrationRule('topic', 'Change room topic', eventType: 'm.room.topic'),
  AdministrationRule(
    'avatar',
    'Change room picture',
    eventType: 'm.room.avatar',
  ),
  AdministrationRule(
    'access',
    'Change room access',
    eventType: 'm.room.join_rules',
  ),
  AdministrationRule(
    'history',
    'Change history visibility',
    eventType: 'm.room.history_visibility',
  ),
  AdministrationRule('pins', 'Pin messages', eventType: 'm.room.pinned_events'),
  AdministrationRule(
    'channels',
    'Link, unlink and reorder channels',
    eventType: 'm.space.child',
  ),
  AdministrationRule(
    'categories',
    'Edit categories and channel layout',
    eventType: 'net.deltiecord.space.channels',
    fallback: 100,
  ),
  AdministrationRule(
    'packs',
    'Publish, link, edit and remove server packs',
    eventType: 'im.ponies.room_emotes',
  ),
  AdministrationRule(
    'roles',
    'Edit role names, colours and assignments',
    eventType: spaceRolesEventType,
  ),
  AdministrationRule(
    'pages',
    'Edit welcome and community rules',
    eventType: 'net.deltiecord.space.pages',
  ),
];

class AdministrationRoom {
  const AdministrationRoom({
    required this.id,
    required this.name,
    required this.powerLevels,
    required this.canEdit,
  });
  final String id;
  final String name;
  final Map<String, dynamic> powerLevels;
  final bool canEdit;
}

class SpaceAdministration {
  const SpaceAdministration({
    required this.roles,
    required this.rooms,
    required this.members,
    required this.canEditRoles,
    required this.ownPower,
  });
  final SpaceRoles roles;
  final List<AdministrationRoom> rooms;
  final Map<String, String> members;
  final bool canEditRoles;
  final int ownPower;
}
