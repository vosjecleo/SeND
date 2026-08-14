import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as flutter_webrtc;
import 'package:matrix/matrix.dart';

import '../models/chat_models.dart';
import 'deltiecord_webrtc_delegate.dart';

/// Owns MatrixRTC/WebRTC resources independently from session and timeline
/// state. Exactly one room call may be active for a client at a time.
class MatrixVoiceController extends ChangeNotifier {
  MatrixVoiceController(this._client, {required this.friendlyError});

  final Client _client;
  final String Function(Object error) friendlyError;
  VoIP? _voip;
  GroupCallSession? _activeCall;
  StreamSubscription<MatrixRTCCallEvent>? _callSubscription;
  VoiceConnectionStatus _status = VoiceConnectionStatus.disconnected;
  bool _muted = false;
  String? _error;
  String? _activeSpeakerUserId;
  List<AudioInputSummary> _audioInputs = const [];
  String? _selectedAudioInputId;
  bool _disposed = false;

  VoiceConnectionStatus get status => _status;
  String? get activeRoomId => _activeCall?.room.id;
  bool get muted => _muted;
  String? get error => _error;
  String? get activeSpeakerUserId => _activeSpeakerUserId;
  List<AudioInputSummary> get audioInputs => _audioInputs;
  String? get selectedAudioInputId => _selectedAudioInputId;

  void initialize() {
    if (!_client.isLogged() || _voip != null || _disposed) return;
    _voip = VoIP(
      _client,
      DeltiecordWebRtcDelegate(
        isCallActive: () =>
            _status == VoiceConnectionStatus.connecting ||
            _status == VoiceConnectionStatus.connected,
      ),
    );
    unawaited(refreshAudioInputs());
  }

  Future<void> refreshAudioInputs() async {
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
      if (_selectedAudioInputId != null &&
          !_audioInputs.any((input) => input.id == _selectedAudioInputId)) {
        _selectedAudioInputId = null;
      }
    } catch (_) {
      if (_disposed) return;
      _audioInputs = const [];
    }
    notifyListeners();
  }

  Future<void> selectAudioInput(String? deviceId) async {
    if (_selectedAudioInputId == deviceId || _disposed) return;
    final reconnectRoomId = activeRoomId;
    _selectedAudioInputId = deviceId;
    notifyListeners();
    if (reconnectRoomId != null) {
      await leave();
      await join(reconnectRoomId);
    }
  }

  Future<void> join(String roomId) async {
    if (_disposed ||
        (activeRoomId == roomId &&
            _status == VoiceConnectionStatus.connected)) {
      return;
    }
    if (_activeCall != null) await leave();
    final room = _client.getRoomById(roomId);
    if (room == null) return;
    initialize();
    final voip = _voip;
    if (voip == null) return;
    _status = VoiceConnectionStatus.connecting;
    _error = null;
    notifyListeners();
    try {
      final call = await voip.fetchOrCreateGroupCall(
        room.id,
        room,
        MeshBackend(),
        'm.call',
        'm.room',
      );
      if (_disposed) return;
      _activeCall = call;
      await _callSubscription?.cancel();
      _callSubscription = call.matrixRTCEventStream.stream.listen(
        _handleCallEvent,
      );
      final audioConstraints = <String, dynamic>{
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        if (_selectedAudioInputId != null)
          'deviceId': {'exact': _selectedAudioInputId},
      };
      final stream = await flutter_webrtc.navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints,
        'video': false,
      });
      if (_disposed || !identical(call, _activeCall)) {
        for (final track in stream.getTracks()) {
          track.stop();
        }
        return;
      }
      await call.enter(
        stream: WrappedMediaStream(
          stream: stream,
          participant: call.localParticipant!,
          room: room,
          client: _client,
          purpose: SDPStreamMetadataPurpose.Usermedia,
          audioMuted: false,
          videoMuted: true,
          isGroupCall: true,
          voip: voip,
        ),
      );
      _status = VoiceConnectionStatus.connected;
    } catch (exception) {
      _status = VoiceConnectionStatus.error;
      _error = friendlyError(exception);
      _activeCall = null;
    }
    if (!_disposed) notifyListeners();
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
            VoiceConnectionStatus.connecting,
          GroupCallState.leaving => VoiceConnectionStatus.disconnecting,
          GroupCallState.ended || GroupCallState.localCallFeedUninitialized =>
            VoiceConnectionStatus.disconnected,
        };
      case GroupCallStateError(:final msg):
        _status = VoiceConnectionStatus.error;
        _error = msg;
      case GroupCallLocalMutedChanged(:final muted, :final kind):
        if (kind == MediaInputKind.audioinput) _muted = muted;
      case GroupCallActiveSpeakerChanged(:final participant):
        _activeSpeakerUserId = participant.userId;
      default:
        break;
    }
    notifyListeners();
  }

  Future<void> setMuted(bool muted) async {
    final call = _activeCall;
    if (call == null || _disposed) return;
    await call.backend.setDeviceMuted(call, muted, MediaInputKind.audioinput);
    _muted = muted;
    notifyListeners();
  }

  Future<void> leave() async {
    final call = _activeCall;
    if (call == null) return;
    _status = VoiceConnectionStatus.disconnecting;
    if (!_disposed) notifyListeners();
    try {
      await call.leave();
    } finally {
      await _callSubscription?.cancel();
      _callSubscription = null;
      _activeCall = null;
      _activeSpeakerUserId = null;
      _muted = false;
      _status = VoiceConnectionStatus.disconnected;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(leave());
    super.dispose();
  }
}
