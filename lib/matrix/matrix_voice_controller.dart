import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';

import '../models/chat_models.dart';
import '../models/rtc_connectivity.dart';
import '../services/app_sounds.dart';
import '../services/screen_capture_service.dart';
import 'rtc/rtc_protocol.dart';
import 'rtc/rtc_matrix_client.dart';
import 'rtc/rtc_transport_api.dart';
import 'rtc/rtc_sfu_session.dart';
import 'rtc/rtc_room_membership.dart';

/// Platform boundary for WebRTC's process-wide audio output selection.
abstract interface class RtcAudioOutputSelector {
  Future<void> select(String deviceId);
}

final class WebRtcAudioOutputSelector implements RtcAudioOutputSelector {
  const WebRtcAudioOutputSelector();

  @override
  Future<void> select(String deviceId) =>
      flutter_webrtc.Helper.selectAudioOutput(deviceId);
}

/// Owns MatrixRTC/WebRTC resources independently from session and timeline
/// state. Matrix handles membership and keys; LiveKit handles SFU media.
/// Exactly one call may be active at a time, including while a join is pending.
class MatrixVoiceController extends ChangeNotifier {
  MatrixVoiceController(
    this._client, {
    required this.friendlyError,
    this.canRingRoom,
    this.onHistoryJoined,
    this.onHistoryLeft,
    RtcAudioOutputSelector? audioOutputSelector,
    RtcTransportApi Function(Client)? transportApiFactory,
    RtcSfuSession Function(Room, RtcTransport, AppPreferences, RtcTransportApi)?
    sessionFactory,
  }) : _audioOutputSelector =
           audioOutputSelector ?? const WebRtcAudioOutputSelector(),
       _apiFactory = transportApiFactory ?? RtcTransportApi.new,
       _sessionFactory =
           sessionFactory ??
           ((room, transport, preferences, api) => RtcSfuSession(
             matrixRoom: room,
             transport: transport,
             preferences: preferences,
             api: api,
           ));

  final Client _client;
  final String Function(Object error) friendlyError;
  final bool Function(Room room)? canRingRoom;
  final Future<void> Function(Room room, bool starting)? onHistoryJoined;
  final Future<void> Function(Room room, bool elected)? onHistoryLeft;
  StreamSubscription<Event>? _ringEvents;
  // SDK 10 emits delayed decryptions only through this legacy update stream.
  // ignore: deprecated_member_use
  StreamSubscription<EventUpdate>? _lateRingEvents;
  StreamSubscription<SyncUpdate>? _ringSync;
  Timer? _incomingTimer;
  ({String roomId, String callerName, String callerId})? _incomingCall;
  ({String roomId, String callerName, String callerId})? get incomingCall =>
      _incomingCall;
  final Set<String> _ringEventIds = {};
  Set<String> _remoteUsers = {};
  bool _participantSoundsReady = false;

  bool _mayRing(Room room) => canRingRoom?.call(room) ?? room.isDirectChat;

  void dismissIncomingCall() {
    _incomingTimer?.cancel();
    _incomingCall = null;
    unawaited(AppSounds.stopRingtone());
    if (!_disposed) notifyListeners();
  }

  void handleCallNotification(Event event) {
    if (!event.isRtcNotificationEvent ||
        _disposed ||
        _session != null ||
        _joiningRoomId != null ||
        event.senderId == _client.userID ||
        !_mayRing(event.room) ||
        _client.ignoredUsers.contains(event.senderId)) {
      return;
    }
    final notification = event.tryParseRtcNotificationContent();
    if (notification == null ||
        notification.notificationType != RtcNotificationType.ring ||
        _client.userID == null ||
        !notification.shouldNotifyUser(
          event: event,
          currentUserId: _client.userID!,
          isAlreadyRinging: _incomingCall != null,
        ) ||
        _ringEventIds.contains(event.eventId)) {
      return;
    }
    final remaining = notification
        .getEffectiveTimestamp(event.originServerTs)
        .add(
          notification.cappedLifetime > const Duration(seconds: 30)
              ? const Duration(seconds: 30)
              : notification.cappedLifetime,
        )
        .difference(DateTime.now());
    if (remaining <= Duration.zero) return;
    _ringEventIds.add(event.eventId);
    if (_ringEventIds.length > 128) _ringEventIds.remove(_ringEventIds.first);
    _incomingCallerSeen = false;
    _incomingCall = (
      roomId: event.room.id,
      callerName:
          event.senderFromMemoryOrFallback.displayName ?? event.senderId,
      callerId: event.senderId,
    );
    _incomingTimer = Timer(remaining, dismissIncomingCall);
    if (_callSound) unawaited(AppSounds.startRingtone(duration: remaining));
    notifyListeners();
  }

  final RtcAudioOutputSelector _audioOutputSelector;
  final RtcTransportApi Function(Client) _apiFactory;
  final RtcSfuSession Function(
    Room,
    RtcTransport,
    AppPreferences,
    RtcTransportApi,
  )
  _sessionFactory;
  RtcSfuSession? _session;
  String? _joiningRoomId;
  int _generation = 0;
  Future<void>? _leaving;
  bool _initialized = false, _disposed = false, _rejoining = false;
  bool _muted = false, _deafened = false, _cameraEnabled = false;
  bool _incomingCallerSeen = false, _changingScreenShare = false;
  AppPreferences _preferences = const AppPreferences();
  VoiceConnectionStatus _status = VoiceConnectionStatus.disconnected;
  String? _error;
  List<AudioInputSummary> _audioInputs = const [];
  List<RtcDeviceSummary> _audioOutputs = const [], _cameras = const [];
  String? _selectedAudioInputId, _selectedAudioOutputId, _selectedCameraId;
  final Map<String, double> _participantVolumes = {};
  final Set<String> _locallyMutedParticipants = {};
  bool get _callSound => _preferences.callSound;

  VoiceConnectionStatus get status => _status;
  String? get activeRoomId => _session?.matrixRoom.id ?? _joiningRoomId;
  bool get muted => _muted;
  bool get deafened => _deafened;
  bool get cameraEnabled => _session?.cameraEnabled ?? _cameraEnabled;
  bool get screenSharing => _session?.screenSharing ?? false;
  double get inputLevel => _muted ? 0 : _session?.inputLevel ?? 0;
  String? get error => _error ?? _session?.error;
  String? get activeSpeakerUserId => _session?.activeSpeakerUserId;
  List<AudioInputSummary> get audioInputs => _audioInputs;
  List<RtcDeviceSummary> get audioOutputs => _audioOutputs;
  List<RtcDeviceSummary> get cameras => _cameras;
  String? get selectedAudioInputId => _selectedAudioInputId;
  String? get selectedAudioOutputId => _selectedAudioOutputId;
  String? get selectedCameraId => _selectedCameraId;
  List<RtcMediaStreamSummary> get mediaStreams =>
      _session?.mediaStreams ?? const [];
  RtcConnectivity get connectivity => _status == VoiceConnectionStatus.error
      ? RtcConnectivity(
          state: RtcConnectivityState.unavailable,
          detail: error ?? 'Unable to connect to the call server',
        )
      : _session?.connectivity ?? const RtcConnectivity();
  double participantVolume(String userId) => _participantVolumes[userId] ?? 1;
  bool participantLocallyMuted(String userId) =>
      _locallyMutedParticipants.contains(userId);

  List<RtcMember> membersForRoom(Room room) {
    final result = <String, RtcMember>{};
    final client = _client;
    if (client is RtcMatrixClient) {
      for (final member in client.cachedRtcMembers(room.id)) {
        result[member.deviceIdentity] = member;
      }
      for (final member in client.rtcStateMembers(room.id)) {
        result.putIfAbsent(member.deviceIdentity, () => member);
      }
    }
    for (final event in room.states[rtcCallMemberType]?.values ?? <Event>[]) {
      final member = RtcMember.parse(
        type: event.type,
        sender: event.senderId,
        content: event.content,
        stateKey: event.stateKey,
        timestamp: event is Event ? event.originServerTs : DateTime(1970),
      );
      if (member != null) {
        result.putIfAbsent(member.deviceIdentity, () => member);
      }
    }
    if (_session?.matrixRoom.id == room.id) {
      for (final member in _session!.members) {
        result[member.deviceIdentity] = member;
      }
    }
    return result.values
        .where((member) => rtcUserStillJoined(room, member.userId))
        .toList();
  }

  Future<void> refreshMemberships({String? roomId}) async {
    final client = _client;
    if (_disposed || client is! RtcMatrixClient) return;
    for (final id in roomId == null ? client.rtcStickyRoomIds : [roomId]) {
      if (_disposed) return;
      final room = client.getRoomById(id);
      if (room != null) await client.hydrateRtcMembers(room);
    }
  }

  Future<void> _checkIncomingCall() async {
    final incoming = _incomingCall;
    if (incoming == null || _disposed) return;
    final room = _client.getRoomById(incoming.roomId);
    if (room == null || !_mayRing(room)) {
      dismissIncomingCall();
      return;
    }
    await refreshMemberships(roomId: room.id);
    if (_disposed || !identical(incoming, _incomingCall)) return;
    final members = membersForRoom(room);
    final present = members.any((member) => member.userId == incoming.callerId);
    if (present) _incomingCallerSeen = true;
    final answeredElsewhere = members.any(
      (member) =>
          member.userId == _client.userID &&
          member.deviceId != _client.deviceID,
    );
    // Missing encrypted membership can mean its room key is still arriving.
    // Do not cancel a fresh ring merely because that event is not decrypted.
    if (answeredElsewhere || (_incomingCallerSeen && !present)) {
      dismissIncomingCall();
    }
  }

  void initialize() {
    if (!_client.isLogged() || _initialized || _disposed) return;
    _initialized = true;
    _ringEvents = _client.onTimelineEvent.stream.listen(handleCallNotification);
    // ignore: deprecated_member_use
    _lateRingEvents = _client.onEvent.stream.listen((update) {
      if (update.type != EventUpdateType.decryptedTimelineQueue) return;
      final room = _client.getRoomById(update.roomID);
      if (room != null) {
        handleCallNotification(Event.fromJson(update.content, room));
      }
    });
    _ringSync = _client.onSync.stream.listen(
      (_) => unawaited(_checkIncomingCall()),
    );
    unawaited(refreshAudioInputs());
  }

  AppPreferences get _sessionPreferences => _preferences.copyWith(
    preferredAudioInputId: _selectedAudioInputId ?? '',
    preferredAudioOutputId: _selectedAudioOutputId ?? '',
    preferredCameraId: _selectedCameraId ?? '',
    participantVolumes: Map.of(_participantVolumes),
  );

  void applyPreferences(AppPreferences preferences) {
    final processingChanged =
        _preferences.echoCancellation != preferences.echoCancellation ||
        _preferences.noiseSuppression != preferences.noiseSuppression ||
        _preferences.autoGainControl != preferences.autoGainControl;
    _preferences = preferences;
    _participantVolumes
      ..clear()
      ..addAll(preferences.participantVolumes);
    String? valid(String id, Iterable<String> devices) =>
        id.isEmpty || (devices.isNotEmpty && !devices.contains(id)) ? null : id;
    _selectedAudioInputId = valid(
      preferences.preferredAudioInputId,
      _audioInputs.map((d) => d.id),
    );
    _selectedAudioOutputId = valid(
      preferences.preferredAudioOutputId,
      _audioOutputs.map((d) => d.id),
    );
    _selectedCameraId = valid(
      preferences.preferredCameraId,
      _cameras.map((d) => d.id),
    );
    if (!_callSound || preferences.callVolume <= 0) {
      unawaited(AppSounds.stopRingtone());
    }
    if (_selectedAudioOutputId case final id?) {
      unawaited(_audioOutputSelector.select(id).catchError((_) {}));
    }
    _session?.applyPreferences(_sessionPreferences);
    unawaited(_applyRemoteAudioSettings());
    final roomId = activeRoomId;
    if (processingChanged && roomId != null) {
      unawaited(_rejoinPreservingState(roomId));
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshAudioInputs() async {
    var inputDisappeared = false;
    var cameraDisappeared = false;
    try {
      final devices = await flutter_webrtc.navigator.mediaDevices
          .enumerateDevices();
      if (_disposed) return;
      _audioInputs = devices
          .where((device) => device.kind == 'audioinput')
          .map(
            (device) => AudioInputSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Microphone' : device.label,
            ),
          )
          .toList(growable: false);
      _audioOutputs = devices
          .where((device) => device.kind == 'audiooutput')
          .map(
            (device) => RtcDeviceSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Audio output' : device.label,
            ),
          )
          .toList(growable: false);
      _cameras = devices
          .where((device) => device.kind == 'videoinput')
          .map(
            (device) => RtcDeviceSummary(
              id: device.deviceId,
              label: device.label.isEmpty ? 'Camera' : device.label,
            ),
          )
          .toList(growable: false);
      if (_selectedAudioInputId != null &&
          !_audioInputs.any((input) => input.id == _selectedAudioInputId)) {
        inputDisappeared = true;
        _selectedAudioInputId = null;
      }
      if (_selectedAudioOutputId != null &&
          !_audioOutputs.any((output) => output.id == _selectedAudioOutputId)) {
        _selectedAudioOutputId = null;
      }
      if (_selectedCameraId != null &&
          !_cameras.any((camera) => camera.id == _selectedCameraId)) {
        cameraDisappeared = true;
        _selectedCameraId = null;
      }
    } catch (_) {
      if (_disposed) return;
      _audioInputs = const [];
      _audioOutputs = const [];
      _cameras = const [];
    }
    notifyListeners();
    final roomId = activeRoomId;
    if (roomId != null && (inputDisappeared || cameraDisappeared)) {
      _error = cameraDisappeared && _cameraEnabled
          ? 'The selected camera disappeared; reconnecting with a fallback.'
          : 'The selected audio device disappeared; reconnecting.';
      unawaited(_rejoinPreservingState(roomId));
    }
  }

  Future<void> selectAudioOutput(String? deviceId) async {
    if (_disposed || _selectedAudioOutputId == deviceId) return;
    try {
      await _audioOutputSelector.select(deviceId ?? 'default');
      _selectedAudioOutputId = deviceId;
      _session?.applyPreferences(_sessionPreferences);
      _error = null;
    } catch (exception) {
      _error = friendlyError(exception);
    }
    notifyListeners();
  }

  Future<void> selectCamera(String? deviceId) async {
    if (_disposed || _selectedCameraId == deviceId) return;
    _selectedCameraId = deviceId;
    final roomId = activeRoomId;
    notifyListeners();
    if (roomId != null && _cameraEnabled) {
      await _rejoinPreservingState(roomId);
    }
  }

  Future<void> selectAudioInput(String? deviceId) async {
    if (_selectedAudioInputId == deviceId || _disposed) return;
    final reconnectRoomId = activeRoomId;
    _selectedAudioInputId = deviceId;
    notifyListeners();
    if (reconnectRoomId != null) {
      await _rejoinPreservingState(reconnectRoomId);
    }
  }

  Future<void> join(String roomId) async {
    if (_disposed ||
        (!_rejoining &&
            activeRoomId == roomId &&
            _status == VoiceConnectionStatus.connected)) {
      return;
    }
    await leave();
    if (_disposed) return;
    final generation = ++_generation;
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    initialize();
    dismissIncomingCall();
    _joiningRoomId = roomId;
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.connecting;
    _error = null;
    _remoteUsers = {};
    _participantSoundsReady = false;
    notifyListeners();
    RtcSfuSession? joining;
    try {
      await refreshMemberships(roomId: roomId);
      final starting = _mayRing(room) && membersForRoom(room).isEmpty;
      final api = _apiFactory(_client);
      final transports = await api.discover();
      if (_disposed || generation != _generation) return;
      if (transports.isEmpty) {
        throw StateError(
          'Your homeserver has no MatrixRTC call server configured.',
        );
      }
      final session = joining =
          _sessionFactory(room, transports.first, _sessionPreferences, api)
            ..muted = _muted
            ..deafened = _deafened
            ..cameraEnabled = _cameraEnabled;
      _session = session;
      session.applyRemoteAudio(
        deafen: _deafened,
        locallyMutedUsers: _locallyMutedParticipants,
        participantVolumes: _participantVolumes,
      );
      session.addListener(_sessionChanged);
      await session.start();
      if (_disposed ||
          generation != _generation ||
          !identical(session, _session)) {
        await session.close();
        return;
      }
      _joiningRoomId = null;
      _status = session.status;
      _cameraEnabled = session.cameraEnabled;
      _remoteUsers = session.members.map((m) => m.userId).toSet();
      _participantSoundsReady = true;
      if (_mayRing(room) && !_rejoining) {
        unawaited(
          onHistoryJoined?.call(room, starting).catchError((Object _) {}),
        );
      }
      if (_callSound && !_rejoining) unawaited(AppSounds.callConnected());
      if (starting && !_rejoining && _remoteUsers.isEmpty) {
        try {
          final members = await room.requestParticipants();
          if (_disposed || generation != _generation) return;
          await room.sendRtcNotification(
            type: RtcNotificationType.ring,
            userIds: members
                .where(
                  (member) =>
                      member.id != _client.userID &&
                      member.membership == Membership.join,
                )
                .map((member) => member.id)
                .toList(),
            lifetime: const Duration(seconds: 30),
          );
          if (_callSound && generation == _generation && _remoteUsers.isEmpty) {
            unawaited(AppSounds.startRingtone());
          }
        } catch (exception) {
          _error =
              'Joined the call, but could not notify the other members: ${friendlyError(exception)}';
        }
      }
    } catch (exception) {
      joining?.removeListener(_sessionChanged);
      await joining?.close();
      if (_disposed || generation != _generation) return;
      _session = null;
      _joiningRoomId = null;
      _status = VoiceConnectionStatus.error;
      _error =
          exception is MatrixException && exception.errcode == 'M_FORBIDDEN'
          ? 'This room does not allow MatrixRTC calls. Ask a room admin to enable them.'
          : friendlyError(exception);
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  void _sessionChanged() {
    final session = _session;
    if (_disposed || session == null) return;
    _status = session.status;
    _cameraEnabled = session.cameraEnabled;
    final users = session.members.map((m) => m.userId).toSet();
    if (users.isNotEmpty) unawaited(AppSounds.stopRingtone());
    if (_participantSoundsReady && _callSound && !_rejoining) {
      if (users.difference(_remoteUsers).isNotEmpty) {
        unawaited(AppSounds.callConnected());
      } else if (_remoteUsers.difference(users).isNotEmpty) {
        unawaited(AppSounds.participantLeft());
      }
    }
    _remoteUsers = users;
    notifyListeners();
  }

  Future<void> _applyRemoteAudioSettings({String? userId}) async {
    _session?.applyRemoteAudio(
      deafen: _deafened,
      locallyMutedUsers: _locallyMutedParticipants,
      participantVolumes: _participantVolumes,
    );
  }

  Future<void> setMuted(bool value) async {
    if (_disposed || _muted == value) return;
    _muted = value;
    // The session gates the capture track before awaiting publication changes.
    final pending = _session?.setMuted(value);
    notifyListeners();
    if (_callSound && !_rejoining) unawaited(AppSounds.muteChanged(value));
    await pending;
  }

  Future<void> setDeafened(bool value) async {
    if (_disposed || _deafened == value) return;
    _deafened = value;
    await _applyRemoteAudioSettings();
    if (_callSound && !_rejoining) unawaited(AppSounds.deafenChanged(value));
    if (!_disposed) notifyListeners();
  }

  Future<void> setParticipantVolume(String userId, double volume) async {
    _participantVolumes[userId] = volume.clamp(0, 1);
    await _applyRemoteAudioSettings(userId: userId);
    if (!_disposed) notifyListeners();
  }

  Future<void> setParticipantLocallyMuted(String userId, bool muted) async {
    if (muted) {
      _locallyMutedParticipants.add(userId);
    } else {
      _locallyMutedParticipants.remove(userId);
    }
    await _applyRemoteAudioSettings(userId: userId);
    if (!_disposed) notifyListeners();
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (_disposed || cameraEnabled == enabled) return;
    _cameraEnabled = enabled;
    await _session?.setCameraEnabled(enabled);
    if (!_disposed) notifyListeners();
  }

  Future<void> setScreenSharing(bool enabled) async {
    final session = _session;
    if (_disposed ||
        session == null ||
        screenSharing == enabled ||
        _changingScreenShare) {
      return;
    }
    _changingScreenShare = true;
    _error = null;
    try {
      if (enabled && !await ScreenCaptureService.prepare()) return;
      if (_disposed || !identical(session, _session)) return;
      await session.setScreenSharing(enabled);
    } catch (exception) {
      _error = friendlyError(exception);
    } finally {
      _changingScreenShare = false;
      if (!screenSharing) await ScreenCaptureService.stop();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _rejoinPreservingState(String roomId) async {
    if (_rejoining || _disposed) return;
    _rejoining = true;
    try {
      await join(roomId);
    } finally {
      _rejoining = false;
    }
  }

  Future<void> leave() => _leaving ??= _leave().whenComplete(() {
    _leaving = null;
  });

  Future<void> _leave() async {
    ++_generation;
    dismissIncomingCall();
    _participantSoundsReady = false;
    _remoteUsers = {};
    _joiningRoomId = null;
    final session = _session;
    final room = session?.matrixRoom;
    final recordHistory = room != null && _mayRing(room) && !_rejoining;
    final ownIdentity = '${_client.userID}:${_client.deviceID}';
    final identities = <String>{
      ownIdentity,
      if (room != null) ...membersForRoom(room).map((m) => m.deviceIdentity),
    }.toList()..sort();
    final elected = identities.isEmpty || identities.first == ownIdentity;
    _session = null;
    session?.removeListener(_sessionChanged);
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.disconnecting;
    if (!_disposed) notifyListeners();
    try {
      await session?.close();
      if (recordHistory) {
        unawaited(onHistoryLeft?.call(room, elected).catchError((Object _) {}));
      }
    } finally {
      await ScreenCaptureService.stop();
      _status = _rejoining
          ? VoiceConnectionStatus.reconnecting
          : VoiceConnectionStatus.disconnected;
      _error = null;
      if (!_disposed) notifyListeners();
      if (session != null && _callSound && !_rejoining && !_disposed) {
        unawaited(AppSounds.callDisconnected());
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_ringEvents?.cancel());
    unawaited(_lateRingEvents?.cancel());
    unawaited(_ringSync?.cancel());
    _incomingTimer?.cancel();
    unawaited(leave());
    super.dispose();
  }
}
