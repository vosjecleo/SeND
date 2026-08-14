part of 'matrix_backend.dart';

extension _MatrixSession on MatrixBackend {
  Future<void> _initializeSession() async {
    try {
      await _syncSubscription?.cancel();
      await _loginSubscription?.cancel();
      await _disposeVoice();
      _client?.dispose();
      _client = await createMatrixClient();
      _syncSubscription = _matrix.onSync.stream.listen((_) {
        _loadSettings();
        _notifyBackendListeners();
        unawaited(_refreshRoomMetadata());
        unawaited(_notifyNewMessages());
      });
      _loginSubscription = _matrix.onLoginStateChanged.stream.listen((_) {
        _status = _matrix.isLogged()
            ? SessionStatus.signedIn
            : SessionStatus.signedOut;
        _notifyBackendListeners();
      });
      await _matrix.init();
      _initializeVoice();
      _loadSettings();
      await _notifications.initialize();
      _status = _matrix.isLogged()
          ? SessionStatus.signedIn
          : SessionStatus.signedOut;
      _error = null;
      if (_matrix.isLogged()) {
        unawaited(refreshEncryptionSetup());
        unawaited(_refreshRoomMetadata());
        unawaited(_refreshMediaConfig());
      }
    } catch (exception) {
      _status = SessionStatus.failed;
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _loginSession({
    required Uri homeserver,
    required String username,
    required String password,
  }) async {
    _status = SessionStatus.signingIn;
    _error = null;
    _notifyBackendListeners();
    try {
      await _matrix.checkHomeserver(homeserver);
      await _matrix.login(
        LoginType.mLoginPassword,
        identifier: AuthenticationUserIdentifier(user: username),
        password: password,
        initialDeviceDisplayName: 'Deltiecord Desktop',
      );
      _initializeVoice();
      _status = SessionStatus.signedIn;
      unawaited(_refreshMediaConfig());
      await refreshEncryptionSetup();
    } catch (exception) {
      _status = SessionStatus.signedOut;
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  Future<void> _logoutSession() async {
    _error = null;
    try {
      await _disposeVoice();
      await _closeTimeline();
      await _matrix.logout();
      _selectedRoomId = null;
      _selectedSpaceId = null;
      _loadedBackupRoomIds.clear();
      _avatarBytes.clear();
      _avatarUris.clear();
      _senderAvatarBytes.clear();
      _senderAvatarUris.clear();
      _decryptedPreviews.clear();
      _replyPreviews.clear();
      _linkPreviews.clear();
      _outboundSessionsReset.clear();
      _roomsMarkingRead.clear();
      _lastMarkedReadEventIds.clear();
      _firstUnreadEventIds.clear();
      _lastNotificationEventIds.clear();
      _roomPresentationOverrides.clear();
      _notificationsPrimed = false;
      _maximumUploadBytes = null;
      _mediaPlaybackSources.clear();
      _mediaRangeProxy.clear();
      _encryptionSetup = const EncryptionSetupState(
        status: EncryptionSetupStatus.loading,
      );
      _status = SessionStatus.signedOut;
    } catch (exception) {
      _error = _friendlyError(exception);
    }
    _notifyBackendListeners();
  }

  void _initializeVoice() {
    if (!_matrix.isLogged() || _voice != null) return;
    _voice = MatrixVoiceController(_matrix, friendlyError: _friendlyError)
      ..addListener(_notifyBackendListeners)
      ..initialize();
  }

  Future<void> _disposeVoice() async {
    final voice = _voice;
    if (voice == null) return;
    _voice = null;
    voice.removeListener(_notifyBackendListeners);
    await voice.leave();
    voice.dispose();
  }

  Future<void> _refreshAudioInputs() async => _voice?.refreshAudioInputs();

  Future<void> _selectAudioInput(String? deviceId) async =>
      _voice?.selectAudioInput(deviceId);

  Future<void> _joinVoiceRoom(String roomId) async {
    _initializeVoice();
    await _voice?.join(roomId);
  }

  Future<void> _setVoiceMuted(bool muted) async => _voice?.setMuted(muted);

  Future<void> _leaveVoiceRoom() async => _voice?.leave();

  Future<void> _setComposerTyping(bool typing) async {
    final room = _matrix.getRoomById(_selectedRoomId ?? '');
    if (room == null || room.isSpace) return;
    _typingStopTimer?.cancel();
    if (typing) {
      if (_typingRoomId != room.id) {
        final oldRoom = _matrix.getRoomById(_typingRoomId ?? '');
        if (oldRoom != null) unawaited(oldRoom.setTyping(false));
      }
      _typingRoomId = room.id;
      await room.setTyping(true, timeout: 5000);
      _typingStopTimer = Timer(const Duration(seconds: 4), () {
        unawaited(setComposerTyping(false));
      });
    } else {
      if (_typingRoomId == room.id) await room.setTyping(false);
      _typingRoomId = null;
    }
  }

  Future<void> _notifyNewMessages() async {
    if (!_matrix.isLogged()) return;
    final rooms = _joinedRooms.where((room) => !room.isSpace);
    if (!_notificationsPrimed) {
      for (final room in rooms) {
        final eventId = room.lastEvent?.eventId;
        if (eventId != null) _lastNotificationEventIds[room.id] = eventId;
      }
      _notificationsPrimed = true;
      return;
    }
    for (final room in rooms) {
      final event = room.lastEvent;
      if (event == null ||
          _lastNotificationEventIds[room.id] == event.eventId) {
        continue;
      }
      _lastNotificationEventIds[room.id] = event.eventId;
      if (room.id == _selectedRoomId ||
          event.senderId == _matrix.userID ||
          room.pushRuleState == PushRuleState.dontNotify ||
          (room.pushRuleState == PushRuleState.mentionsOnly &&
              room.highlightCount == 0)) {
        continue;
      }
      var displayEvent = event;
      if (event.type == EventTypes.Encrypted && _matrix.encryption != null) {
        try {
          displayEvent = await _matrix.encryption!.decryptRoomEvent(event);
        } catch (_) {
          // A key arriving later will still update the room preview. The
          // notification must remain useful without delaying sync forever.
        }
      }
      final sender = event.senderFromMemoryOrFallback.calcDisplayname();
      final notificationBody = !_notificationPreviewsEnabled
          ? 'New message'
          : displayEvent.type == EventTypes.Message
          ? displayEvent.calcUnlocalizedBody(
              hideReply: true,
              hideEdit: true,
              plaintextBody: true,
            )
          : 'New room activity';
      await _notifications.show(
        title: '$sender in ${room.getLocalizedDisplayname()}',
        body: notificationBody,
      );
    }
  }

  void _loadSettings() {
    final content =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    _notificationPreviewsEnabled =
        content?.tryGet<bool>('notification_previews') ?? true;
  }

  Future<void> _setNotificationPreviewsEnabled(bool enabled) async {
    if (_matrix.userID == null) return;
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    try {
      await _matrix.setAccountData(
        _matrix.userID!,
        MatrixBackend._settingsAccountDataType,
        {...?existing, 'notification_previews': enabled},
      );
      _notificationPreviewsEnabled = enabled;
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
  }

  void _clearSessionError() {
    _error = null;
    _notifyBackendListeners();
  }
}
