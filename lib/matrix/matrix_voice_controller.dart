import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';

import '../models/chat_models.dart';
import '../models/rtc_connectivity.dart';
import '../services/app_sounds.dart';
import '../services/rtc_audio_controls.dart';
import '../services/screen_capture_service.dart';
import 'deltiecord_webrtc_delegate.dart';
import 'refreshing_voip.dart';

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
/// state. This uses matrix-dart-sdk's MatrixRTC model and flutter-webrtc's
/// native bindings; see CREDITS.md. Exactly one call may be active at a time.
class MatrixVoiceController extends ChangeNotifier {
  MatrixVoiceController(
    this._client, {
    required this.friendlyError,
    this.canRingRoom,
    RtcAudioOutputSelector? audioOutputSelector,
  }) : _audioOutputSelector =
           audioOutputSelector ?? const WebRtcAudioOutputSelector();

  final Client _client;
  final String Function(Object error) friendlyError;
  final bool Function(Room room)? canRingRoom;
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
        _activeCall != null ||
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

  void _checkIncomingCall() {
    final incoming = _incomingCall;
    if (incoming == null) return;
    final room = _client.getRoomById(incoming.roomId);
    if (room == null || !_mayRing(room)) {
      dismissIncomingCall();
      return;
    }
    bool present(String userId) =>
        (room.states[EventTypes.GroupCallMember]?.values ?? <Event>[])
            .where((event) => event.senderId == userId)
            .any(
              (event) => (event.content['memberships'] as List? ?? const [])
                  .whereType<Map>()
                  .any(
                    (entry) =>
                        entry['expires_ts'] is num &&
                        (entry['expires_ts'] as num) >
                            DateTime.now().millisecondsSinceEpoch,
                  ),
            );
    // Stop on caller hangup, or when another device on this account picks up.
    if (!present(incoming.callerId) || present(_client.userID!)) {
      dismissIncomingCall();
    }
  }

  final RtcAudioOutputSelector _audioOutputSelector;
  RefreshingVoIP? _voip;
  GroupCallSession? _activeCall;
  StreamSubscription<MatrixRTCCallEvent>? _callSubscription;
  VoiceConnectionStatus _status = VoiceConnectionStatus.disconnected;
  bool _muted = false;
  bool _deafened = false;
  bool _cameraEnabled = false;
  bool _screenSharing = false;
  bool _changingScreenShare = false;
  String? _error;
  String? _activeSpeakerUserId;
  List<AudioInputSummary> _audioInputs = const [];
  String? _selectedAudioInputId;
  List<RtcDeviceSummary> _audioOutputs = const [];
  String? _selectedAudioOutputId;
  List<RtcDeviceSummary> _cameras = const [];
  String? _selectedCameraId;
  final Map<String, double> _participantVolumes = {};
  final Set<String> _locallyMutedParticipants = {};
  Timer? _inputMeterTimer;
  double _inputLevel = 0;
  bool _samplingInput = false;
  bool _rejoining = false;
  bool _disposed = false;
  bool _echoCancellation = true;
  bool _noiseSuppression = true;
  bool _autoGainControl = true;
  double _microphoneVolume = 1;
  double _outputVolume = 1;
  bool _callSound = true;
  bool _shareDesktopAudio = false;
  final Set<flutter_webrtc.RTCPeerConnection> _peers = {};
  final Map<String, flutter_webrtc.RTCVideoRenderer> _webAudio = {};
  bool _updatingWebAudio = false;
  bool _webAudioDirty = false;
  Timer? _connectivityTimer;
  bool _samplingConnectivity = false;
  RtcConnectivity _connectivity = const RtcConnectivity();
  RtcConnectivity get connectivity => _status == VoiceConnectionStatus.error
      ? RtcConnectivity(
          state: RtcConnectivityState.unavailable,
          detail: _error ?? 'Unable to connect',
        )
      : _connectivity;

  VoiceConnectionStatus get status => _status;
  String? get activeRoomId => _activeCall?.room.id;
  bool get muted => _muted;
  bool get deafened => _deafened;
  bool get cameraEnabled => _cameraEnabled;
  bool get screenSharing => _screenSharing;
  double get inputLevel => _muted ? 0 : _inputLevel;
  String? get error => _error;
  String? get activeSpeakerUserId => _activeSpeakerUserId;
  List<AudioInputSummary> get audioInputs => _audioInputs;
  String? get selectedAudioInputId => _selectedAudioInputId;
  List<RtcDeviceSummary> get audioOutputs => _audioOutputs;
  String? get selectedAudioOutputId => _selectedAudioOutputId;
  List<RtcDeviceSummary> get cameras => _cameras;
  String? get selectedCameraId => _selectedCameraId;

  List<RtcMediaStreamSummary> get mediaStreams {
    final call = _activeCall;
    if (call == null) return const [];
    final streams = [
      ...call.backend.userMediaStreams.map((stream) => (stream, false)),
      ...call.backend.screenShareStreams.map((stream) => (stream, true)),
    ];
    return streams
        .where(
          (entry) =>
              entry.$1.stream != null &&
              entry.$1.stream!.getVideoTracks().isNotEmpty,
        )
        .map(
          (entry) => RtcMediaStreamSummary(
            id: entry.$1.id,
            userId: entry.$1.participant.userId,
            displayName: entry.$1.displayName ?? entry.$1.participant.userId,
            stream: entry.$1.stream!,
            local: entry.$1.isLocal(),
            screenShare: entry.$2,
            videoMuted: entry.$1.isVideoMuted(),
          ),
        )
        .toList(growable: false);
  }

  double participantVolume(String userId) => _participantVolumes[userId] ?? 1;

  bool participantLocallyMuted(String userId) =>
      _locallyMutedParticipants.contains(userId);

  void applyPreferences(AppPreferences preferences) {
    final processingChanged =
        _echoCancellation != preferences.echoCancellation ||
        _noiseSuppression != preferences.noiseSuppression ||
        _autoGainControl != preferences.autoGainControl;
    _echoCancellation = preferences.echoCancellation;
    _noiseSuppression = preferences.noiseSuppression;
    _autoGainControl = preferences.autoGainControl;
    _microphoneVolume = preferences.microphoneVolume.clamp(0, 1);
    _outputVolume = preferences.outputVolume.clamp(0, 1);
    _callSound = preferences.callSound;
    if (!_callSound || preferences.callVolume <= 0) {
      unawaited(AppSounds.stopRingtone());
    }
    _shareDesktopAudio = preferences.shareDesktopAudio;
    final inputId = preferences.preferredAudioInputId;
    final outputId = preferences.preferredAudioOutputId;
    final cameraId = preferences.preferredCameraId;
    _selectedAudioInputId =
        inputId.isEmpty ||
            (_audioInputs.isNotEmpty &&
                !_audioInputs.any((device) => device.id == inputId))
        ? null
        : inputId;
    _selectedAudioOutputId =
        outputId.isEmpty ||
            (_audioOutputs.isNotEmpty &&
                !_audioOutputs.any((device) => device.id == outputId))
        ? null
        : outputId;
    _selectedCameraId =
        cameraId.isEmpty ||
            (_cameras.isNotEmpty &&
                !_cameras.any((device) => device.id == cameraId))
        ? null
        : cameraId;
    _participantVolumes
      ..clear()
      ..addAll(preferences.participantVolumes);
    final selectedOutputId = _selectedAudioOutputId;
    if (selectedOutputId != null) {
      unawaited(
        _audioOutputSelector.select(selectedOutputId).catchError((_) {}),
      );
    }
    unawaited(_applyRemoteAudioSettings());
    unawaited(_applyLocalInputVolume());
    final roomId = activeRoomId;
    if (processingChanged && roomId != null) {
      unawaited(_rejoinPreservingState(roomId));
    }
    notifyListeners();
  }

  void initialize() {
    if (!_client.isLogged() || _voip != null || _disposed) return;
    _ringEvents = _client.onTimelineEvent.stream.listen(handleCallNotification);
    // ignore: deprecated_member_use
    _lateRingEvents = _client.onEvent.stream.listen((update) {
      if (update.type != EventUpdateType.decryptedTimelineQueue) return;
      final room = _client.getRoomById(update.roomID);
      if (room != null) {
        handleCallNotification(Event.fromJson(update.content, room));
      }
    });
    _ringSync = _client.onSync.stream.listen((_) => _checkIncomingCall());
    _voip = RefreshingVoIP(
      _client,
      DeltiecordWebRtcDelegate(
        isCallActive: () =>
            _status == VoiceConnectionStatus.connecting ||
            _status == VoiceConnectionStatus.reconnecting ||
            _status == VoiceConnectionStatus.connected,
        shareDesktopAudio: () => _shareDesktopAudio,
        onPeerConnection: (peer) {
          if (!_disposed && _activeCall != null) _peers.add(peer);
        },
      ),
    );
    unawaited(refreshAudioInputs());
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
      if (kIsWeb) await _syncWebAudio();
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
        (activeRoomId == roomId &&
            _status == VoiceConnectionStatus.connected)) {
      return;
    }
    if (_activeCall != null) await leave();
    dismissIncomingCall();
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    initialize();
    final voip = _voip;
    if (voip == null) return;
    final startingCall = _mayRing(room) && !room.hasActiveGroupCall(voip);
    _remoteUsers = {};
    _participantSoundsReady = false;
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.connecting;
    _error = null;
    notifyListeners();
    GroupCallSession? joiningCall;
    try {
      final call = joiningCall = await voip.fetchOrCreateGroupCall(
        room.id,
        room,
        MeshBackend(),
        'm.call',
        'm.room',
      );
      if (_disposed) return;
      _activeCall = call;
      voip.beginJoining(call);
      // Reserve this group before publishing membership. The SDK normally
      // does so only AFTER entering, rejecting early peer invites as "busy".
      voip.currentGroupCID = voip.groupCalls.keys.firstWhere(
        (id) => identical(voip.groupCalls[id], call),
      );
      _connectivity = const RtcConnectivity();
      _connectivityTimer?.cancel();
      _connectivityTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_sampleConnectivity()),
      );
      await _callSubscription?.cancel();
      _callSubscription = call.matrixRTCEventStream.stream.listen(
        _handleCallEvent,
      );
      final audioConstraints = <String, dynamic>{
        'echoCancellation': _echoCancellation,
        'noiseSuppression': _noiseSuppression,
        'autoGainControl': _autoGainControl,
        'volume': _microphoneVolume,
        if (_selectedAudioInputId != null)
          'deviceId': {'exact': _selectedAudioInputId},
      };
      flutter_webrtc.MediaStream stream;
      try {
        stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
          'video': _cameraEnabled
              ? {
                  'width': {'ideal': 1280},
                  'height': {'ideal': 720},
                  if (_selectedCameraId != null)
                    'deviceId': {'exact': _selectedCameraId},
                }
              : false,
        });
      } catch (exception) {
        if (!_cameraEnabled) rethrow;
        _cameraEnabled = false;
        _error = 'Camera unavailable; joined with audio only.';
        stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
          'audio': audioConstraints,
          'video': false,
        });
      }
      if (_disposed || !identical(call, _activeCall)) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        return;
      }
      // A pre-muted join must not transmit while Matrix finishes entering.
      setRtcAudioMuted(stream.getAudioTracks(), _muted);
      await call.enter(
        stream: WrappedMediaStream(
          stream: stream,
          participant: call.localParticipant!,
          room: room,
          client: _client,
          purpose: SDPStreamMetadataPurpose.Usermedia,
          audioMuted: _muted,
          videoMuted: !_cameraEnabled,
          isGroupCall: true,
          voip: voip,
        ),
      );
      voip.finishJoining();
      if (_disposed || !identical(call, _activeCall)) return;
      _status = VoiceConnectionStatus.connected;
      if (_muted) {
        await call.backend.setDeviceMuted(
          call,
          true,
          MediaInputKind.audioinput,
        );
      }
      _applyLocalMuteGate();
      _startInputMeter();
      await _applyLocalInputVolume();
      await _applyRemoteAudioSettings();
      if (_callSound && !_rejoining) unawaited(AppSounds.callConnected());
      _remoteUsers = call.participants
          .where((p) => !p.isLocal)
          .map((p) => p.userId)
          .toSet();
      _participantSoundsReady = true;
      if (startingCall && !_rejoining && _remoteUsers.isEmpty) {
        try {
          final members = await room.requestParticipants();
          if (!identical(call, _activeCall) || _disposed) return;
          await room.sendRtcNotification(
            type: RtcNotificationType.ring,
            userIds: members
                .where(
                  (user) =>
                      user.id != _client.userID &&
                      user.membership == Membership.join,
                )
                .map((user) => user.id)
                .toList(),
            lifetime: const Duration(seconds: 30),
          );
          if (_callSound &&
              identical(call, _activeCall) &&
              call.participants.every((p) => p.isLocal)) {
            unawaited(AppSounds.startRingtone());
          }
        } catch (exception) {
          _error =
              'Joined the call, but could not notify the other members: ${friendlyError(exception)}';
        }
      }
    } catch (exception) {
      try {
        await joiningCall?.leave();
      } catch (_) {
        try {
          if (joiningCall != null) {
            await joiningCall.backend.dispose(joiningCall);
          }
        } catch (_) {}
      }
      _status = VoiceConnectionStatus.error;
      _error = friendlyError(exception);
      _activeCall = null;
      voip.currentGroupCID = null;
      voip.finishJoining();
      _connectivityTimer?.cancel();
      _peers.clear();
      if (kIsWeb) await _syncWebAudio();
    }
    if (!_disposed) notifyListeners();
  }

  void _startInputMeter() {
    _inputMeterTimer?.cancel();
    _inputMeterTimer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => unawaited(_sampleInputLevel()),
    );
  }

  Future<void> _sampleConnectivity() async {
    final call = _activeCall;
    if (call != null && _participantSoundsReady) {
      final users = call.participants
          .where((p) => !p.isLocal)
          .map((p) => p.userId)
          .toSet();
      if (users.isNotEmpty) unawaited(AppSounds.stopRingtone());
      if (_callSound && !_rejoining) {
        if (users.difference(_remoteUsers).isNotEmpty) {
          unawaited(AppSounds.callConnected());
        } else if (_remoteUsers.difference(users).isNotEmpty) {
          unawaited(AppSounds.participantLeft());
        }
      }
      _remoteUsers = users;
    }
    if (_disposed || call == null || _samplingConnectivity) return;
    _samplingConnectivity = true;
    var connected = 0;
    var failed = 0;
    var total = 0;
    int? ping;
    try {
      for (final peer in _peers.toList()) {
        try {
          final state = await peer.getConnectionState().timeout(
            const Duration(seconds: 2),
          );
          if (state ==
              flutter_webrtc
                  .RTCPeerConnectionState
                  .RTCPeerConnectionStateClosed) {
            _peers.remove(peer);
            continue;
          }
          total++;
          if (state ==
              flutter_webrtc
                  .RTCPeerConnectionState
                  .RTCPeerConnectionStateFailed) {
            failed++;
          }
          if (state !=
              flutter_webrtc
                  .RTCPeerConnectionState
                  .RTCPeerConnectionStateConnected) {
            continue;
          }
          connected++;
          final stats = await peer.getStats().timeout(
            const Duration(seconds: 2),
          );
          final measured = rtcPingMilliseconds(
            stats
                .where((report) => report.type == 'candidate-pair')
                .map((report) => Map<String, dynamic>.from(report.values)),
          );
          if (measured != null) ping = max(ping ?? 0, measured);
        } catch (_) {
          // A peer may close between polling and reading statistics.
        }
      }
      if (_disposed || !identical(call, _activeCall)) return;
      total = max(
        total,
        call.participants.where((participant) => !participant.isLocal).length,
      );
      _connectivity = RtcConnectivity(
        state: connected > 0 && connected == total
            ? RtcConnectivityState.connected
            : failed > 0 && connected == 0
            ? RtcConnectivityState.unavailable
            : RtcConnectivityState.waiting,
        connectedPeers: connected,
        totalPeers: total,
        pingMilliseconds: ping,
        detail: connected > 0 && connected == total
            ? 'RTC connected ($connected peer${connected == 1 ? '' : 's'})'
            : failed > 0 && connected == 0
            ? 'RTC connection failed. Check network/TURN, then rejoin.'
            : total == 0
            ? 'Room joined; waiting for another participant / RTC'
            : 'Room joined; RTC connected to $connected of $total peers',
      );
      notifyListeners();
    } finally {
      _samplingConnectivity = false;
    }
  }

  Future<void> _sampleInputLevel() async {
    final call = _activeCall;
    if (call == null || _samplingInput || _disposed || _muted) {
      if (_inputLevel != 0) {
        _inputLevel = 0;
        if (!_disposed) notifyListeners();
      }
      return;
    }
    _samplingInput = true;
    var sampled = 0.0;
    try {
      for (final peerConnection in _peers.toList()) {
        final reports = await peerConnection.getStats();
        for (final report in reports) {
          if (report.type != 'media-source' ||
              report.values['kind'] != 'audio') {
            continue;
          }
          final level = report.values['audioLevel'];
          if (level is num) sampled = max(sampled, level.toDouble());
        }
      }
    } catch (_) {
      // WebRTC stats availability varies by Linux backend.
    } finally {
      _samplingInput = false;
    }
    if ((_inputLevel - sampled).abs() >= 0.01) {
      _inputLevel = sampled.clamp(0, 1);
      if (!_disposed) notifyListeners();
    }
  }

  void _handleCallEvent(MatrixRTCCallEvent event) {
    if (_disposed) return;
    switch (event) {
      case GroupCallStateChanged(:final state):
        _status = switch (state) {
          GroupCallState.entered => VoiceConnectionStatus.connected,
          GroupCallState.entering ||
          GroupCallState.initializingLocalCallFeed ||
          GroupCallState.localCallFeedInitialized =>
            _rejoining
                ? VoiceConnectionStatus.reconnecting
                : VoiceConnectionStatus.connecting,
          GroupCallState.leaving =>
            _rejoining
                ? VoiceConnectionStatus.reconnecting
                : VoiceConnectionStatus.disconnecting,
          GroupCallState.ended || GroupCallState.localCallFeedUninitialized =>
            VoiceConnectionStatus.disconnected,
        };
      case GroupCallStateError(:final msg):
        _status = _activeCall?.state == GroupCallState.entered
            ? VoiceConnectionStatus.connected
            : VoiceConnectionStatus.error;
        _error = msg;
      case GroupCallLocalMutedChanged(:final muted, :final kind):
        // Ignore old acknowledgements after a newer local toggle.
        if (kind == MediaInputKind.audioinput) _applyLocalMuteGate();
        if (kind == MediaInputKind.videoinput) _cameraEnabled = !muted;
      case GroupCallActiveSpeakerChanged(:final participant):
        _activeSpeakerUserId = participant.userId;
      case GroupCallLocalScreenshareStateChanged(:final screensharing):
        _screenSharing = screensharing;
        if (!screensharing) unawaited(ScreenCaptureService.stop());
      case GroupCallStreamAdded() ||
          GroupCallStreamRemoved() ||
          GroupCallStreamReplaced():
        _applyLocalMuteGate();
        unawaited(_applyRemoteAudioSettings());
      default:
        break;
    }
    notifyListeners();
  }

  Future<void> setDeafened(bool deafened) async {
    if (_deafened == deafened || _disposed) return;
    _deafened = deafened;
    await _applyRemoteAudioSettings();
    if (_callSound && !_rejoining) unawaited(AppSounds.deafenChanged(deafened));
    notifyListeners();
  }

  Future<void> setParticipantVolume(String userId, double volume) async {
    _participantVolumes[userId] = volume.clamp(0, 1);
    await _applyRemoteAudioSettings(userId: userId);
    notifyListeners();
  }

  Future<void> setParticipantLocallyMuted(String userId, bool muted) async {
    if (muted) {
      _locallyMutedParticipants.add(userId);
    } else {
      _locallyMutedParticipants.remove(userId);
    }
    await _applyRemoteAudioSettings(userId: userId);
    notifyListeners();
  }

  Future<void> _applyRemoteAudioSettings({String? userId}) async {
    if (kIsWeb) {
      await _syncWebAudio();
      return;
    }
    final call = _activeCall;
    if (call == null) return;
    for (final wrapped in [
      ...call.backend.userMediaStreams,
      ...call.backend.screenShareStreams,
    ]) {
      if (wrapped.isLocal() ||
          (userId != null && wrapped.participant.userId != userId)) {
        continue;
      }
      final muted =
          _deafened ||
          _locallyMutedParticipants.contains(wrapped.participant.userId);
      await applyRtcRemoteAudio(
        tracks: wrapped.stream?.getAudioTracks() ?? const [],
        muted: muted,
        volume: participantVolume(wrapped.participant.userId) * _outputVolume,
        setVolume: flutter_webrtc.Helper.setVolume,
      );
    }
  }

  Future<void> _syncWebAudio() async {
    _webAudioDirty = true;
    if (_updatingWebAudio) return;
    _updatingWebAudio = true;
    try {
      while (_webAudioDirty) {
        _webAudioDirty = false;
        final call = _activeCall;
        final streams = call == null
            ? <WrappedMediaStream>[]
            : [
                    ...call.backend.userMediaStreams,
                    ...call.backend.screenShareStreams,
                  ]
                  .where(
                    (wrapped) =>
                        !wrapped.isLocal() &&
                        (wrapped.stream?.getAudioTracks().isNotEmpty ?? false),
                  )
                  .toList();
        final ids = streams.map((wrapped) => wrapped.id).toSet();
        for (final id
            in _webAudio.keys.where((id) => !ids.contains(id)).toList()) {
          final renderer = _webAudio.remove(id)!;
          renderer.srcObject = null;
          await renderer.dispose();
        }
        for (final wrapped in streams) {
          var renderer = _webAudio[wrapped.id];
          if (renderer == null) {
            renderer = flutter_webrtc.RTCVideoRenderer();
            await renderer.initialize();
            if (_disposed || !identical(call, _activeCall)) {
              await renderer.dispose();
              break;
            }
            _webAudio[wrapped.id] = renderer;
          }
          // Browsers need an audio element even for audio-only streams.
          // Its lifetime belongs to the call, not to a visible video tile.
          if (renderer.srcObject != wrapped.stream) {
            renderer.srcObject = wrapped.stream;
          }
          final userId = wrapped.participant.userId;
          final muted = _deafened || _locallyMutedParticipants.contains(userId);
          setRtcAudioMuted(
            wrapped.stream!.getAudioTracks(),
            muted || participantVolume(userId) * _outputVolume == 0,
          );
          renderer.muted = muted;
          await renderer.setVolume(
            muted ? 0 : participantVolume(userId) * _outputVolume,
          );
          if (_selectedAudioOutputId case final output?) {
            await renderer.audioOutput(output);
          }
        }
      }
    } catch (_) {
      // Output selection/autoplay support varies; keep RTC transport health
      // separate from browser playback policy.
    } finally {
      _updatingWebAudio = false;
    }
  }

  Future<void> _applyLocalInputVolume() async {
    final call = _activeCall;
    if (call == null) return;
    for (final wrapped in call.backend.userMediaStreams.where(
      (stream) => stream.isLocal(),
    )) {
      for (final track in wrapped.stream?.getAudioTracks() ?? const []) {
        try {
          await flutter_webrtc.Helper.setVolume(_microphoneVolume, track);
        } catch (_) {
          // Some Linux capture backends expose processing but not gain.
        }
      }
    }
  }

  Future<void> setCameraEnabled(bool enabled) async {
    if (_disposed || _cameraEnabled == enabled) return;
    final call = _activeCall;
    final hasVideoTrack =
        call?.backend.localUserMediaStream?.stream
            ?.getVideoTracks()
            .isNotEmpty ??
        false;
    if (call != null && (hasVideoTrack || !enabled)) {
      _cameraEnabled = enabled;
      notifyListeners();
      if (hasVideoTrack) {
        try {
          await call.backend.setDeviceMuted(
            call,
            !enabled,
            MediaInputKind.videoinput,
          );
        } catch (exception) {
          _cameraEnabled = !enabled;
          _error = friendlyError(exception);
          notifyListeners();
          rethrow;
        }
      }
      return;
    }
    _cameraEnabled = enabled;
    final roomId = activeRoomId;
    notifyListeners();
    if (roomId != null) {
      await _rejoinPreservingState(roomId);
    }
  }

  Future<void> _rejoinPreservingState(String roomId) async {
    if (_rejoining || _disposed) return;
    _rejoining = true;
    _status = VoiceConnectionStatus.reconnecting;
    notifyListeners();
    final wasMuted = _muted;
    final wasDeafened = _deafened;
    try {
      await leave();
      await join(roomId);
      if (_status == VoiceConnectionStatus.connected) {
        if (wasMuted) await setMuted(true);
        if (wasDeafened) await setDeafened(true);
      }
    } finally {
      _rejoining = false;
    }
  }

  Future<void> setScreenSharing(bool enabled) async {
    final call = _activeCall;
    if (call == null ||
        _disposed ||
        _screenSharing == enabled ||
        _changingScreenShare) {
      return;
    }
    if (enabled &&
        (_status != VoiceConnectionStatus.connected ||
            call.localParticipant == null ||
            _connectivity.connectedPeers == 0)) {
      _error =
          'Wait for another participant to connect before sharing your screen.';
      notifyListeners();
      return;
    }
    _error = null;
    _changingScreenShare = true;
    try {
      if (enabled) {
        if (!await ScreenCaptureService.prepare()) return;
        if (_disposed ||
            !identical(call, _activeCall) ||
            _status != VoiceConnectionStatus.connected ||
            _connectivity.connectedPeers == 0) {
          return;
        }
      }
      await call.backend.setScreensharingEnabled(call, enabled, '');
      if (_disposed || !identical(call, _activeCall)) {
        await call.backend.setScreensharingEnabled(call, false, '');
        return;
      }
      _screenSharing = call.backend.localScreenshareStream != null;
    } catch (exception) {
      _error = friendlyError(exception);
      _screenSharing = call.backend.localScreenshareStream != null;
    } finally {
      _changingScreenShare = false;
      if (!_screenSharing) await ScreenCaptureService.stop();
    }
    if (!_disposed) notifyListeners();
  }

  void _applyLocalMuteGate() {
    final call = _activeCall;
    if (call == null) return;
    final local = call.backend.localUserMediaStream;
    if (local != null) {
      if (local.isAudioMuted() != _muted) local.setAudioMuted(_muted);
      setRtcAudioMuted(local.stream?.getAudioTracks() ?? const [], _muted);
    }
    for (final wrapped in call.backend.userMediaStreams) {
      if (wrapped.isLocal()) {
        if (wrapped.isAudioMuted() != _muted) wrapped.setAudioMuted(_muted);
        setRtcAudioMuted(wrapped.stream?.getAudioTracks() ?? const [], _muted);
      }
    }
    // Mesh calls clone the microphone stream for each peer. Muting only the
    // original capture stream is insufficient if SDK device enumeration fails.
    for (final peer in _voip?.calls.values ?? const <CallSession>[]) {
      if (peer.room.id != call.room.id ||
          peer.groupCallId != call.groupCallId) {
        continue;
      }
      final microphone = peer.localUserMediaStream;
      if (microphone == null) continue;
      if (microphone.isAudioMuted() != _muted) microphone.setAudioMuted(_muted);
      setRtcAudioMuted(microphone.stream?.getAudioTracks() ?? const [], _muted);
    }
    if (_muted) {
      _inputLevel = 0;
      if (_activeSpeakerUserId == _client.userID) _activeSpeakerUserId = null;
    }
  }

  Future<void> setMuted(bool muted) async {
    if (_disposed || _muted == muted) return;
    _muted = muted;
    // Do not depend on device enumeration/signalling to disable capture.
    _applyLocalMuteGate();
    notifyListeners();
    if (_callSound && !_rejoining) unawaited(AppSounds.muteChanged(muted));
    final call = _activeCall;
    if (call == null) return;
    try {
      await call.backend.setDeviceMuted(call, muted, MediaInputKind.audioinput);
    } catch (exception) {
      _error = friendlyError(exception);
      notifyListeners();
      rethrow;
    } finally {
      _applyLocalMuteGate();
    }
  }

  Future<void> leave() async {
    dismissIncomingCall();
    _participantSoundsReady = false;
    _remoteUsers = {};
    _voip?.currentGroupCID = null;
    _voip?.finishJoining();
    _connectivityTimer?.cancel();
    _peers.clear();
    _connectivity = const RtcConnectivity();
    final call = _activeCall;
    if (call == null) {
      await ScreenCaptureService.stop();
      _status = VoiceConnectionStatus.disconnected;
      _error = null;
      if (!_disposed) notifyListeners();
      return;
    }
    _status = _rejoining
        ? VoiceConnectionStatus.reconnecting
        : VoiceConnectionStatus.disconnecting;
    if (!_disposed) notifyListeners();
    final playDisconnectSound = _callSound && !_rejoining && !_disposed;
    try {
      await call.leave();
    } finally {
      _inputMeterTimer?.cancel();
      _inputMeterTimer = null;
      _inputLevel = 0;
      await _callSubscription?.cancel();
      _callSubscription = null;
      _activeCall = null;
      _activeSpeakerUserId = null;
      if (kIsWeb) await _syncWebAudio();
      _screenSharing = false;
      await ScreenCaptureService.stop();
      _status = _rejoining
          ? VoiceConnectionStatus.reconnecting
          : VoiceConnectionStatus.disconnected;
      if (!_disposed) notifyListeners();
      if (playDisconnectSound) unawaited(AppSounds.callDisconnected());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_ringEvents?.cancel());
    unawaited(_lateRingEvents?.cancel());
    unawaited(_ringSync?.cancel());
    _incomingTimer?.cancel();
    _inputMeterTimer?.cancel();
    _connectivityTimer?.cancel();
    unawaited(leave());
    super.dispose();
  }
}
