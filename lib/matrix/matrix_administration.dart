part of 'matrix_backend.dart';

extension _MatrixAdministration on MatrixBackend {
  Future<Map<String, dynamic>> _optionalRoomState(
    String roomId,
    String type,
  ) async {
    try {
      return Map<String, dynamic>.from(
        await _matrix.getRoomStateWithKey(roomId, type, ''),
      );
    } on MatrixException catch (error) {
      if (error.errcode == 'M_NOT_FOUND') return {};
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _channelJoinRule(String spaceId) async {
    final rule = (await _optionalRoomState(
      spaceId,
      spacePolicyEventType,
    ))['default_channel_access'];
    return {
      'join_rule': rule == 'restricted' || rule == 'public' ? rule : 'invite',
      if (rule == 'restricted')
        'allow': [
          {'type': 'm.room_membership', 'room_id': spaceId},
        ],
    };
  }

  Future<void> _discoverSpaceRooms(String spaceId) async {
    if (!_discoveringSpaces.add(spaceId)) return;
    final client = _matrix;
    try {
      final found = <RoomSummary>[];
      String? next;
      final seen = <String>{};
      do {
        final page = await client.getSpaceHierarchy(
          spaceId,
          maxDepth: 1,
          limit: 100,
          from: next,
        );
        for (final room in page.rooms) {
          if (room.roomId == spaceId ||
              room.roomType == 'm.space' ||
              !seen.add(room.roomId)) {
            continue;
          }
          if (!{
                'public',
                'restricted',
                'knock_restricted',
              }.contains(room.joinRule) &&
              client.getRoomById(room.roomId)?.membership !=
                  Membership.invite) {
            continue;
          }
          found.add(
            RoomSummary(
              id: room.roomId,
              name: room.name ?? room.canonicalAlias ?? room.roomId,
              lastMessage: 'Open to join channel',
              unreadCount: 0,
              usesChannelIcon: true,
              topic: room.topic ?? '',
            ),
          );
        }
        next = page.nextBatch;
      } while (next != null);
      if (!identical(client, _client)) return;
      _discoveredSpaceRooms[spaceId] = found;
      _notifyBackendListeners();
    } catch (_) {
      // Joined rooms remain usable offline; never wipe a successful listing.
    } finally {
      _discoveringSpaces.remove(spaceId);
    }
  }

  Future<RoomAccessSettings> _getRoomAccessSettings(String roomId) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('Join this room to edit its settings.');
    final access = await _optionalRoomState(roomId, EventTypes.RoomJoinRules);
    final history = await _optionalRoomState(
      roomId,
      'm.room.history_visibility',
    );
    final policy = await _optionalRoomState(roomId, spacePolicyEventType);
    final directory = await _matrix.getRoomVisibilityOnDirectory(roomId);
    return RoomAccessSettings(
      roomId: roomId,
      joinRule: access['join_rule'] as String? ?? 'invite',
      historyVisibility: history['history_visibility'] as String? ?? 'shared',
      discoverable: directory == Visibility.public,
      canEditAccess: room.canChangeStateEvent(EventTypes.RoomJoinRules),
      canEditHistory: room.canChangeStateEvent('m.room.history_visibility'),
      canEditPolicy: room.canChangeStateEvent(spacePolicyEventType),
      defaultChannelAccess:
          policy['default_channel_access'] as String? ?? 'invite',
      roomVersion:
          room.getState(EventTypes.RoomCreate)?.content['room_version']
              as String? ??
          '1',
      eventVisibility: RoomEventVisibility.fromJson({
        'defaults': policy['event_visibility'],
      }).defaults,
      allowedSpaceIds: [
        for (final item in (access['allow'] as List? ?? const []))
          if (item is Map &&
              item['type'] == 'm.room_membership' &&
              item['room_id'] is String)
            item['room_id'] as String,
      ],
    );
  }

  Future<void> _setRoomAccess(
    String roomId,
    String rule, {
    String? spaceId,
  }) async {
    if (!{'public', 'invite', 'restricted', 'knock'}.contains(rule)) {
      throw ArgumentError('Unsupported access rule');
    }
    final current = await _optionalRoomState(roomId, EventTypes.RoomJoinRules);
    final allowed = (current['allow'] as List? ?? []).whereType<Map>().toList();
    if (rule == 'restricted') {
      if (spaceId == null) throw StateError('Choose a parent Space first.');
      if (!allowed.any(
        (entry) =>
            entry['type'] == 'm.room_membership' && entry['room_id'] == spaceId,
      )) {
        allowed.add({'type': 'm.room_membership', 'room_id': spaceId});
      }
    }
    await _matrix.setRoomStateWithKey(roomId, EventTypes.RoomJoinRules, '', {
      ...current,
      'join_rule': rule,
      if (rule == 'restricted') 'allow': allowed,
    });
    if (spaceId != null) await _discoverSpaceRooms(spaceId);
  }

  Future<void> _setRoomHistoryVisibility(String roomId, String value) async {
    if (!{'invited', 'joined', 'shared', 'world_readable'}.contains(value)) {
      throw ArgumentError('Invalid history visibility');
    }
    await _matrix.setRoomStateWithKey(roomId, 'm.room.history_visibility', '', {
      'history_visibility': value,
    });
  }

  Future<void> _setSpacePolicy(
    String spaceId,
    String access,
    Map<String, bool> visibility,
  ) async {
    if (!{'invite', 'restricted', 'public'}.contains(access)) {
      throw ArgumentError('Invalid default access');
    }
    final previous = await _optionalRoomState(spaceId, spacePolicyEventType);
    await _matrix.setRoomStateWithKey(spaceId, spacePolicyEventType, '', {
      ...previous,
      'version': 1,
      'default_channel_access': access,
      'event_visibility': {
        for (final event in CosmeticRoomEvent.values)
          if (visibility.containsKey(event.name))
            event.name: visibility[event.name],
      },
    });
    _notifyBackendListeners();
  }

  SpaceRoles _rolesForSpace(String? spaceId) => SpaceRoles.fromJson(
    _client?.getRoomById(spaceId ?? '')?.getState(spaceRolesEventType)?.content,
  );

  SpaceRoles _rolesForRoom(Room room) {
    final space = _spaceForRoom(room);
    return _rolesForSpace(space?.id);
  }

  Room? _spaceForRoom(Room room) {
    final parents =
        _matrix.rooms
            .where(
              (space) =>
                  space.isSpace &&
                  space.membership == Membership.join &&
                  (space.id == room.id ||
                      space.spaceChildren.any(
                        (child) => child.roomId == room.id,
                      )),
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    return parents.where((space) => space.id == _selectedSpaceId).firstOrNull ??
        parents.firstOrNull;
  }

  Future<SpaceAdministration> _getSpaceAdministration(String spaceId) async {
    final space = _matrix.getRoomById(spaceId);
    if (space == null || !space.isSpace) {
      throw StateError('Space is unavailable.');
    }
    final members = await space.requestParticipants();
    var roles = const SpaceRoles();
    try {
      roles = SpaceRoles.fromJson(
        Map<String, dynamic>.from(
          await _matrix.getRoomStateWithKey(spaceId, spaceRolesEventType, ''),
        ),
      );
    } on MatrixException catch (error) {
      if (error.errcode != 'M_NOT_FOUND') rethrow;
    }
    _reviewedSpaceRoles[spaceId] = roles;
    final children = space.spaceChildren
        .map((child) => child.roomId)
        .whereType<String>()
        .toSet();
    final administrationRooms = <AdministrationRoom>[];
    for (final id in {spaceId, ...children}) {
      final room = _matrix.getRoomById(id);
      try {
        final powers = await _optionalRoomState(id, EventTypes.RoomPowerLevels);
        final ownPower =
            (powers['users'] as Map?)?[_matrix.userID] as int? ??
            powers['users_default'] as int? ??
            0;
        administrationRooms.add(
          AdministrationRoom(
            id: id,
            name: room?.getLocalizedDisplayname() ?? id,
            powerLevels: powers,
            ownPower: ownPower,
            canEdit: room?.canChangePowerLevel ?? false,
          ),
        );
      } catch (_) {
        administrationRooms.add(
          AdministrationRoom(
            id: id,
            name:
                '${room?.getLocalizedDisplayname() ?? id} (unavailable — join/check access)',
            powerLevels: const {},
            canEdit: false,
          ),
        );
      }
    }
    return SpaceAdministration(
      roles: roles,
      rooms: administrationRooms,
      members: {
        for (final member in members) member.id: member.calcDisplayname(),
      },
      canEditRoles:
          space.canChangePowerLevel &&
          space.canChangeStateEvent(spaceRolesEventType),
      ownPower: space.ownPowerLevel.level,
    );
  }

  Future<void> _saveSpaceRoles(
    String spaceId,
    SpaceRoles roles, {
    SpaceRoles? expected,
  }) async {
    final space = _matrix.getRoomById(spaceId);
    if (space == null ||
        !space.canChangePowerLevel ||
        !space.canChangeStateEvent(spaceRolesEventType)) {
      throw StateError('You cannot edit roles in this Space.');
    }
    if (roles.roles.length > 100 ||
        roles.roles.any(
          (role) =>
              role.id.isEmpty ||
              role.name.trim().isEmpty ||
              role.name.length > 80 ||
              role.powerLevel < 0 ||
              role.powerLevel > space.ownPowerLevel.level,
        ) ||
        roles.roles.map((role) => role.id).toSet().length !=
            roles.roles.length) {
      throw StateError(
        'Role names, IDs or levels are invalid, or exceed your authority.',
      );
    }
    final valid = roles.roles.map((role) => role.id).toSet();
    if (roles.members.values.any((ids) => !valid.containsAll(ids))) {
      throw StateError('Unknown role assignment.');
    }
    final current = SpaceRoles.fromJson(
      await _optionalRoomState(spaceId, spaceRolesEventType),
    );
    final reviewed = expected ?? _reviewedSpaceRoles[spaceId];
    if (reviewed == null || !current.equivalentTo(reviewed)) {
      throw StateError(
        'Roles changed since you opened this page. Reload before saving.',
      );
    }
    await _matrix.setRoomStateWithKey(
      spaceId,
      spaceRolesEventType,
      '',
      roles.toJson(),
    );
    _reviewedSpaceRoles[spaceId] = roles;
    _notifyBackendListeners();
  }

  Future<void> _setAdministrationRule(
    String roomId,
    AdministrationRule rule,
    int level,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null ||
        !room.canChangePowerLevel ||
        !administrationRules.contains(rule) ||
        level < 0 ||
        level > room.ownPowerLevel.level) {
      throw StateError('You cannot set this permission level.');
    }
    // Re-read before each individual change rather than replacing a stale UI
    // snapshot. Unknown fields and permissions edited by other clients survive.
    final current = Map<String, dynamic>.from(
      await _matrix.getRoomStateWithKey(roomId, EventTypes.RoomPowerLevels, ''),
    );
    if (rule.level(current) > room.ownPowerLevel.level) {
      throw StateError('This permission exceeds your authority.');
    }
    await _matrix.setRoomStateWithKey(
      roomId,
      EventTypes.RoomPowerLevels,
      '',
      rule.apply(current, level),
    );
    _notifyBackendListeners();
  }

  Future<void> _applySpaceRolePower(
    String spaceId,
    String roomId,
    SpaceRoles reviewedRoles,
  ) async {
    final space = _matrix.getRoomById(spaceId);
    final room = _matrix.getRoomById(roomId);
    if (space == null ||
        room == null ||
        !space.canChangePowerLevel ||
        !room.canChangePowerLevel ||
        (roomId != spaceId &&
            !_roomsForSpace(spaceId).any((child) => child.id == roomId))) {
      throw StateError('You cannot apply these roles to this room.');
    }
    final rawRoles = await _matrix.getRoomStateWithKey(
      spaceId,
      spaceRolesEventType,
      '',
    );
    final roles = SpaceRoles.fromJson(Map<String, dynamic>.from(rawRoles));
    if (!roles.equivalentTo(reviewedRoles)) {
      throw StateError(
        'Roles changed since you reviewed them. Reload administration before applying.',
      );
    }
    final current = Map<String, dynamic>.from(
      await _matrix.getRoomStateWithKey(roomId, EventTypes.RoomPowerLevels, ''),
    );
    final updated = applyRolePowerLevels(
      current: current,
      roles: roles,
      spaceId: spaceId,
      actorId: _matrix.userID!,
      actorPower: room.ownPowerLevel.level,
    );
    await _matrix.setRoomStateWithKey(
      roomId,
      EventTypes.RoomPowerLevels,
      '',
      updated,
    );
    _notifyBackendListeners();
  }
}
