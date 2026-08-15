part of 'matrix_backend.dart';

extension _MatrixRoomOperations on MatrixBackend {
  void _selectSpace(String? spaceId) {
    if (_selectedSpaceId == spaceId) return;
    _selectedSpaceId = spaceId;
    _selectedRoomId = null;
    _closeTimeline();
    _notifyBackendListeners();
  }

  Future<void> _selectRoom(String roomId) async {
    if (_selectedRoomId == roomId && _timeline != null) return;
    await _closeTimeline();
    final generation = _timelineGeneration;
    _selectedRoomId = roomId;
    _timelineLoading = true;
    _error = null;
    _notifyBackendListeners();
    try {
      final room = _matrix.getRoomById(roomId);
      if (room == null) throw StateError('That room is no longer available.');
      await room.postLoad();
      if (_presentationFor(room) == RoomPresentation.voice) {
        _timelineLoading = false;
        _notifyBackendListeners();
        return;
      }
      await _loadRoomBackupKeys(room);
      if (!_isCurrentSelection(roomId, generation)) return;
      final timeline = await room.getTimeline(
        onUpdate: () => _onTimelineUpdate(generation),
      );
      if (!_isCurrentSelection(roomId, generation)) {
        timeline.cancelSubscriptions();
        return;
      }
      _timeline = timeline;
      _captureFirstUnread(room, timeline);
      await _decryptTimelineEvents(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      await _hydrateTimelineMetadata(timeline);
      if (!_isCurrentTimeline(timeline, generation)) return;
      timeline.requestKeys(tryOnlineBackup: true, onlineKeyBackupOnly: false);
      await _markSelectedRoomRead();
    } catch (exception) {
      if (_isCurrentSelection(roomId, generation)) {
        _error = _friendlyError(exception);
      }
    } finally {
      if (_isCurrentSelection(roomId, generation)) {
        _timelineLoading = false;
        _notifyBackendListeners();
      }
    }
  }

  Future<void> _setRoomPresentation(
    String roomId,
    RoomPresentation presentation,
  ) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await _matrix.setRoomStateWithKey(
        room.id,
        MatrixBackend._roomPresentationEventType,
        '',
        {'kind': presentation.name},
      );
      _roomPresentationOverrides[roomId] = presentation;
      if (roomId == _selectedRoomId) {
        await _closeTimeline();
        _selectedRoomId = null;
        await selectRoom(roomId);
      }
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _createRoom({
    required String name,
    required RoomPresentation presentation,
    required String topic,
    required bool encrypted,
  }) async {
    _error = null;
    try {
      final roomId = await _matrix.createRoom(
        name: name.trim(),
        preset: CreateRoomPreset.privateChat,
        visibility: Visibility.private,
        topic: topic.trim().isEmpty ? null : topic.trim(),
        initialState: encrypted
            ? [
                StateEvent(
                  type: EventTypes.Encryption,
                  stateKey: '',
                  content: {'algorithm': 'm.megolm.v1.aes-sha2'},
                ),
              ]
            : null,
      );
      await _matrix.waitForRoomInSync(roomId, join: true);
      final room = _matrix.getRoomById(roomId);
      if (room == null) {
        throw StateError('The new room did not arrive in sync.');
      }
      if (_selectedSpaceId case final spaceId?) {
        await _matrix.getRoomById(spaceId)?.setSpaceChild(roomId);
      }
      await setRoomPresentation(roomId, presentation);
      await selectRoom(roomId);
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  Future<void> _createSpace({
    required String name,
    required String topic,
  }) async {
    try {
      final roomId = await _matrix.createSpace(
        name: name.trim(),
        topic: topic.trim().isEmpty ? null : topic.trim(),
        visibility: Visibility.private,
        waitForSync: true,
      );
      _selectSpace(roomId);
      unawaited(_refreshRoomMetadata());
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _renameRoom(String roomId, String name) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null || name.trim().isEmpty) return;
    try {
      await room.setName(name.trim());
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _setRoomTopic(String roomId, String topic) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await room.setDescription(topic.trim());
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setRoomAvatar(String roomId, Uint8List? bytes) async {
    final room = _matrix.getRoomById(roomId);
    if (room == null) throw StateError('That room is no longer available.');
    try {
      await room.setAvatar(
        bytes == null
            ? null
            : MatrixFile(bytes: bytes, name: 'room-avatar.png'),
      );
      _avatarUris.remove(roomId);
      await _refreshAvatar(room);
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setMemberPowerLevel(String userId, int powerLevel) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) throw StateError('No room is selected.');
    final member = room.unsafeGetUserFromMemoryOrFallback(userId);
    if (!room.canChangePowerLevel || member.powerLevel >= room.ownPowerLevel) {
      throw StateError('You do not have permission to change this member.');
    }
    if (powerLevel > room.ownPowerLevel.level) {
      throw StateError('You cannot grant a power level above your own.');
    }
    try {
      await room.setPower(userId, powerLevel.clamp(0, 100));
    } catch (exception) {
      _error = _friendlyError(exception);
      rethrow;
    } finally {
      _notifyBackendListeners();
    }
  }

  Future<void> _setSelectedRoomMuted(bool muted) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null) return;
    try {
      await room.setPushRuleState(
        muted ? PushRuleState.dontNotify : PushRuleState.notify,
      );
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  void _captureFirstUnread(Room room, Timeline timeline) {
    if (!room.hasNewMessages) {
      _firstUnreadEventIds[room.id] = null;
      return;
    }
    final markerId =
        room.receiptState.global.latestOwnReceipt?.eventId ??
        (room.fullyRead.isEmpty ? null : room.fullyRead);
    final markerIndex = markerId == null
        ? timeline.events.length
        : timeline.events.indexWhere((event) => event.eventId == markerId);
    final oldestUnreadIndex = markerIndex <= 0
        ? null
        : markerIndex > timeline.events.length
        ? timeline.events.length - 1
        : markerIndex - 1;
    _firstUnreadEventIds[room.id] = oldestUnreadIndex == null
        ? null
        : timeline.events[oldestUnreadIndex].eventId;
  }
}
