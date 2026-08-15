part of 'matrix_backend.dart';

extension _MatrixSession on MatrixBackend {
  Future<void> _initializeSession() async {
    try {
      await _syncSubscription?.cancel();
      await _loginSubscription?.cancel();
      await _syncStatusSubscription?.cancel();
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
      _syncStatusSubscription = _matrix.onSyncStatus.stream.listen((update) {
        _connectionStatus = switch (update.status) {
          SyncStatus.finished ||
          SyncStatus.waitingForResponse => ConnectionStatus.online,
          SyncStatus.processing || SyncStatus.cleaningUp =>
            _connectionStatus == ConnectionStatus.offline
                ? ConnectionStatus.reconnecting
                : ConnectionStatus.online,
          SyncStatus.error => ConnectionStatus.offline,
        };
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
        unawaited(_refreshProfile());
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
    _connectionStatus = ConnectionStatus.connecting;
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
      _connectionStatus = ConnectionStatus.online;
      unawaited(_refreshMediaConfig());
      await refreshEncryptionSetup();
    } catch (exception) {
      _status = SessionStatus.signedOut;
      _connectionStatus = ConnectionStatus.offline;
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
      _deviceSessions = const [];
      _profileDisplayName = null;
      _profileAvatarBytes = null;
      _mediaRangeProxy.clear();
      _encryptionSetup = const EncryptionSetupState(
        status: EncryptionSetupStatus.loading,
      );
      _status = SessionStatus.signedOut;
      _connectionStatus = ConnectionStatus.offline;
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

  Future<void> _refreshDevices() async {
    if (!_matrix.isLogged() || _devicesLoading) return;
    _devicesLoading = true;
    _notifyBackendListeners();
    try {
      final devices = await _matrix.getDevices() ?? const [];
      _deviceSessions =
          devices
              .map(
                (device) => DeviceSessionSummary(
                  id: device.deviceId,
                  displayName: device.displayName?.trim().isNotEmpty == true
                      ? device.displayName!.trim()
                      : 'Unnamed Matrix device',
                  current: device.deviceId == _matrix.deviceID,
                  lastSeenAt: device.lastSeenTs == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!),
                  lastSeenIp: device.lastSeenIp,
                ),
              )
              .toList(growable: false)
            ..sort((a, b) {
              if (a.current != b.current) return a.current ? -1 : 1;
              return (b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                  );
            });
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _devicesLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _refreshProfile() async {
    final userId = _matrix.userID;
    if (userId == null || _profileLoading) return;
    _profileLoading = true;
    _notifyBackendListeners();
    try {
      final profile = await _matrix.getUserProfile(
        userId,
        maxCacheAge: Duration.zero,
      );
      _profileDisplayName = profile.displayname ?? userId;
      final avatar = profile.avatarUrl;
      if (avatar == null || !avatar.isScheme('mxc')) {
        _profileAvatarBytes = null;
      } else {
        final mediaId = avatar.pathSegments.join('/');
        final response = await _matrix.getContentThumbnail(
          avatar.host,
          mediaId,
          192,
          192,
          method: Method.crop,
          animated: false,
        );
        _profileAvatarBytes = response.data;
      }
    } catch (exception) {
      _error = _friendlyError(exception);
    } finally {
      _profileLoading = false;
      _notifyBackendListeners();
    }
  }

  Future<void> _setProfileDisplayName(String displayName) async {
    final userId = _matrix.userID;
    if (userId == null || displayName.trim().isEmpty) return;
    try {
      await _matrix.setProfileField(userId, 'displayname', {
        'displayname': displayName.trim(),
      });
      _profileDisplayName = displayName.trim();
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _setProfileAvatar(
    Uint8List? bytes, {
    required String fileName,
    required String mimeType,
  }) async {
    try {
      await _matrix.setAvatar(
        bytes == null
            ? null
            : MatrixFile(bytes: bytes, name: fileName, mimeType: mimeType),
      );
      _profileAvatarBytes = bytes;
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _removeDevice(String targetDeviceId, String password) async {
    if (targetDeviceId == _matrix.deviceID) {
      throw StateError('Log out to remove the device currently in use.');
    }
    await _runPasswordUia(
      password,
      (auth) => _matrix.deleteDevice(targetDeviceId, auth: auth),
    );
    await _refreshDevices();
  }

  Future<void> _deleteAccount(String password) async {
    await _runPasswordUia(
      password,
      (auth) => _matrix.deactivateAccount(auth: auth, erase: true),
    );
    try {
      await _matrix.logout();
    } catch (_) {
      // Deactivation commonly invalidates the token before logout can run.
    }
    _status = SessionStatus.signedOut;
    _connectionStatus = ConnectionStatus.offline;
    _notifyBackendListeners();
  }

  Future<T> _runPasswordUia<T>(
    String password,
    Future<T> Function(AuthenticationData? auth) request,
  ) async {
    if (password.isEmpty) throw ArgumentError('Enter your account password.');
    try {
      return await request(null);
    } on MatrixException catch (exception) {
      if (!exception.requireAdditionalAuthentication) rethrow;
      return request(
        AuthenticationPassword(
          session: exception.session,
          password: password,
          identifier: AuthenticationUserIdentifier(user: _matrix.userID!),
        ),
      );
    }
  }

  Future<void> _joinVoiceRoom(String roomId) async {
    _initializeVoice();
    await _voice?.join(roomId);
  }

  Future<void> _setVoiceMuted(bool muted) async => _voice?.setMuted(muted);

  Future<void> _leaveVoiceRoom() async => _voice?.leave();

  Future<void> _setComposerTyping(bool typing) async {
    if (!_preferences.sendTypingNotifications) return;
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
    if (!_matrix.isLogged() || !_preferences.notificationsEnabled) return;
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
        sound: _preferences.notificationSound,
      );
    }
  }

  void _loadSettings() {
    final content =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    _notificationPreviewsEnabled =
        content?.tryGet<bool>('notification_previews') ?? true;
    if (_pendingPreferences != null) return;
    _preferences = AppPreferences(
      density: content?.tryGet<String>('density') == 'cozy'
          ? InterfaceDensity.cozy
          : InterfaceDensity.compact,
      fontScale:
          (content?['font_scale'] as num?)?.toDouble().clamp(0.8, 1.4) ?? 1,
      roomPanelWidth:
          (content?['room_panel_width'] as num?)?.toDouble().clamp(220, 420) ??
          280,
      reducedMotion: content?.tryGet<bool>('reduced_motion') ?? false,
      highContrast: content?.tryGet<bool>('high_contrast') ?? false,
      autoplayGifs: content?.tryGet<bool>('autoplay_gifs') ?? true,
      notificationsEnabled:
          content?.tryGet<bool>('notifications_enabled') ?? true,
      notificationSound: content?.tryGet<bool>('notification_sound') ?? true,
      sendReadReceipts: content?.tryGet<bool>('send_read_receipts') ?? true,
      sendTypingNotifications:
          content?.tryGet<bool>('send_typing_notifications') ?? true,
      sharePresence: content?.tryGet<bool>('share_presence') ?? true,
      accentColor: content?.tryGet<int>('accent_color') ?? 0xff6975d9,
      fontFamily: content?.tryGet<String>('font_family') ?? 'System',
      showNativeTitleBar:
          content?.tryGet<bool>('show_native_title_bar') ?? true,
      rememberWindowState:
          content?.tryGet<bool>('remember_window_state') ?? true,
      shortcutBindings: _shortcutBindingsFrom(content),
      sendWithCtrlEnter: content?.tryGet<bool>('send_with_ctrl_enter') ?? false,
      readReceiptMemberThreshold:
          content?.tryGet<int>('receipt_member_threshold') ?? 10,
      timelineChunkSize: content?.tryGet<int>('timeline_chunk_size') ?? 30,
      timelineChunkCap: content?.tryGet<int>('timeline_chunk_cap') ?? 3,
    );
  }

  Map<AppShortcutAction, String> _shortcutBindingsFrom(
    Map<String, Object?>? content,
  ) {
    final result = <AppShortcutAction, String>{...defaultShortcutBindings};
    final stored = content?['shortcut_bindings'];
    if (stored is! Map) return result;
    for (final entry in stored.entries) {
      final action = AppShortcutAction.values
          .where((candidate) => candidate.name == entry.key)
          .firstOrNull;
      if (action != null) result[action] = entry.value.toString();
    }
    return result;
  }

  Future<void> _updatePreferences(AppPreferences preferences) async {
    if (_matrix.userID == null) return;
    if (preferences.sharePresence != _preferences.sharePresence) {
      unawaited(
        _matrix
            .setPresence(
              _matrix.userID!,
              preferences.sharePresence
                  ? PresenceType.online
                  : PresenceType.offline,
            )
            .catchError((_) {}),
      );
    }
    _preferences = preferences;
    _pendingPreferences = preferences;
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(const Duration(milliseconds: 300), () {
      final pending = _pendingPreferences;
      if (pending != null) unawaited(_persistPreferences(pending));
    });
    _notifyBackendListeners();
  }

  Future<void> _persistPreferences(AppPreferences preferences) async {
    if (_matrix.userID == null) return;
    final existing =
        _matrix.accountData[MatrixBackend._settingsAccountDataType]?.content;
    try {
      await _matrix.setAccountData(
        _matrix.userID!,
        MatrixBackend._settingsAccountDataType,
        {
          ...?existing,
          'density': preferences.density.name,
          'font_scale': preferences.fontScale,
          'room_panel_width': preferences.roomPanelWidth,
          'reduced_motion': preferences.reducedMotion,
          'high_contrast': preferences.highContrast,
          'autoplay_gifs': preferences.autoplayGifs,
          'notifications_enabled': preferences.notificationsEnabled,
          'notification_sound': preferences.notificationSound,
          'send_read_receipts': preferences.sendReadReceipts,
          'send_typing_notifications': preferences.sendTypingNotifications,
          'share_presence': preferences.sharePresence,
          'accent_color': preferences.accentColor,
          'font_family': preferences.fontFamily,
          'show_native_title_bar': preferences.showNativeTitleBar,
          'remember_window_state': preferences.rememberWindowState,
          'shortcut_bindings': {
            for (final entry in preferences.shortcutBindings.entries)
              entry.key.name: entry.value,
          },
          'send_with_ctrl_enter': preferences.sendWithCtrlEnter,
          'receipt_member_threshold': preferences.readReceiptMemberThreshold,
          'timeline_chunk_size': preferences.timelineChunkSize,
          'timeline_chunk_cap': preferences.timelineChunkCap,
        },
      );
      if (identical(_pendingPreferences, preferences)) {
        _pendingPreferences = null;
      }
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
    }
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
