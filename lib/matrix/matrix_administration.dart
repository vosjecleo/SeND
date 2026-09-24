part of 'matrix_backend.dart';

extension _MatrixAdministration on MatrixBackend {
  SpaceRoles _rolesForSpace(String? spaceId) => SpaceRoles.fromJson(
    _client?.getRoomById(spaceId ?? '')?.getState(spaceRolesEventType)?.content,
  );

  SpaceRoles _rolesForRoom(Room room) {
    final spaceId = _selectedSpaceId;
    if (spaceId == null ||
        (room.id != spaceId &&
            !_roomsForSpace(spaceId).any((child) => child.id == room.id))) {
      return const SpaceRoles();
    }
    return _rolesForSpace(spaceId);
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
    return SpaceAdministration(
      roles: roles,
      rooms: [
        for (final room in [space, ..._roomsForSpace(spaceId)])
          AdministrationRoom(
            id: room.id,
            name: room.getLocalizedDisplayname(),
            powerLevels: Map<String, dynamic>.from(
              await _matrix.getRoomStateWithKey(
                room.id,
                EventTypes.RoomPowerLevels,
                '',
              ),
            ),
            canEdit: room.canChangePowerLevel,
          ),
      ],
      members: {
        for (final member in members) member.id: member.calcDisplayname(),
      },
      canEditRoles:
          space.canChangePowerLevel &&
          space.canChangeStateEvent(spaceRolesEventType),
      ownPower: space.ownPowerLevel.level,
    );
  }

  Future<void> _saveSpaceRoles(String spaceId, SpaceRoles roles) async {
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
    await _matrix.setRoomStateWithKey(
      spaceId,
      spaceRolesEventType,
      '',
      roles.toJson(),
    );
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
