import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:matrix/matrix.dart' as matrix;
import '../../models/chat_models.dart';
import '../../services/socks_proxy.dart';
import '../../models/rtc_connectivity.dart';
import 'rtc_audio_gain.dart';
import 'rtc_log_security.dart';
import 'rtc_membership_session.dart';
import 'rtc_key_provider.dart';
import 'rtc_matrix_client.dart';
import 'rtc_protocol.dart';
import 'rtc_room_membership.dart';
import 'rtc_transport_api.dart';

class _SfuConnection {
  _SfuConnection(this.room, this.listener);
  final lk.Room room;
  final lk.EventsListener<lk.RoomEvent> listener;
}

/// Native call presentation is unchanged. One room publishes local tracks;
/// other SFU rooms only subscribe, so microphone/camera capture is never
/// duplicated across federation. Matrix handles all media-key exchange.
class RtcSfuSession extends ChangeNotifier {
  static const _membershipError =
      'Call membership or media keys could not be refreshed. Retrying.';
  RtcSfuSession({
    required this.matrixRoom,
    required this.transport,
    required this.preferences,
    required this.api,
    this.muted = false,
    this.deafened = false,
    this.cameraEnabled = false,
    this.onProgress,
  });
  final matrix.Room matrixRoom;
  final RtcTransport transport;
  final RtcTransportApi api;
  final void Function(String)? onProgress;
  AppPreferences preferences;
  bool muted, deafened, cameraEnabled;
  bool screenSharing = false;
  bool _closed = false, _keyPaused = true, _connectingRemotes = false;
  bool _started = false;
  lk.BaseKeyProvider? _provider;
  RtcMembershipSession? _membership;
  lk.Room? _primary;
  lk.LocalAudioTrack? _microphone;
  final _connections = <String, _SfuConnection>{};
  final _transportConnections = <String, String>{};
  final _retryAfter = <String, DateTime>{};
  final _encryptionStates = <String, lk.E2EEState>{};
  Map<String, int> get cryptoDiagnostics => {
    'ready': _encryptionStates.values
        .where((s) => s == lk.E2EEState.kOk)
        .length,
    'missing': _encryptionStates.values
        .where((s) => s == lk.E2EEState.kMissingKey)
        .length,
    'failed': _encryptionStates.values
        .where(
          (s) => [
            lk.E2EEState.kEncryptionFailed,
            lk.E2EEState.kDecryptionFailed,
            lk.E2EEState.kInternalError,
          ].contains(s),
        )
        .length,
  };
  bool get microphoneTrackEnabled =>
      _microphone?.mediaStreamTrack.enabled == true;
  bool get remoteAudioDisabled => _connections.values.every(
    (connection) => connection.room.remoteParticipants.values.every(
      (participant) => participant.audioTrackPublications.every(
        (pub) => pub.track?.mediaStreamTrack.enabled != true,
      ),
    ),
  );
  Timer? _timer;
  Future<void>? _starting, _closing;
  Completer<void>? _remoteConnectionDone;
  String? error;
  VoiceConnectionStatus status = VoiceConnectionStatus.connecting;
  RtcConnectivity connectivity = const RtcConnectivity();
  Set<String> locallyMuted = {};
  Map<String, double> volumes = {};
  List<RtcMember> get members => (_membership?.members ?? const <RtcMember>[])
      .where(
        (member) =>
            member.expiresAt.isAfter(DateTime.now()) &&
            rtcUserStillJoined(matrixRoom, member.userId),
      )
      .toList();
  double get inputLevel =>
      muted || _keyPaused ? 0 : _primary?.localParticipant?.audioLevel ?? 0;
  String? get activeSpeakerUserId {
    for (final connection in _connections.values) {
      for (final speaker in connection.room.activeSpeakers) {
        if (speaker.identity == _primary?.localParticipant?.identity &&
            !muted) {
          return matrixRoom.client.userID;
        }
        final member = _memberForIdentity(speaker.identity);
        if (member != null) return member.userId;
      }
    }
    return null;
  }

  RtcMember? _memberForIdentity(String identity) =>
      members.where((m) => m.backendIdentities.contains(identity)).firstOrNull;

  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    if (SocksProxy.blockDirectTraffic) {
      throw StateError(
        'Calls are blocked by your SOCKS proxy settings. WebRTC media cannot use this proxy.',
      );
    }
    onProgress?.call('creating encryption provider');
    await silenceRtcDebugLogging();
    final options = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: Uint8List.fromList(utf8.encode('LKFrameEncryptionKey')),
      ratchetWindowSize: 0,
      keyRingSize: 256,
      failureTolerance: -1,
      discardFrameWhenCryptorNotReady: true,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
    );
    // Capability failures abort before any track is published. No plaintext
    // fallback and no shared, room-wide password masquerading as Matrix E2EE.
    final rawProvider = await rtc.frameCryptorFactory.createDefaultKeyProvider(
      options,
    );
    try {
      _provider = MatrixRtcKeyProvider(rawProvider, options);
    } catch (_) {
      await rawProvider.dispose();
      rethrow;
    }
    if (_closed) {
      await rawProvider.dispose();
      return;
    }
    _membership = RtcMembershipSession(
      room: matrixRoom,
      useSticky:
          matrixRoom.client is RtcMatrixClient &&
          (await matrixRoom.client.getVersions())
                  .unstableFeatures?['org.matrix.msc4354'] ==
              true,
      transport: transport,
      pauseMedia: (paused) async {
        _keyPaused = paused;
        _applyLocalGate();
      },
      installKey: _installKey,
      onMembersChanged: (_) {
        _updateSubscriptions();
        unawaited(_connectRemoteTransports());
        if (!_closed) notifyListeners();
      },
      onError: (failure) {
        onProgress?.call(
          'membership refresh failed (${failure is matrix.MatrixException ? failure.errcode : failure.runtimeType})',
        );
        error = _membershipError;
        _applyLocalGate();
        if (!_closed) notifyListeners();
      },
      onHealthy: () {
        if (error == _membershipError) {
          error = null;
          if (!_closed) notifyListeners();
        }
      },
    );
    onProgress?.call('authorizing transport');
    final credentials = await api.authorize(
      transport: transport,
      roomId: matrixRoom.id,
      memberId: _membership!.memberId,
    );
    if (_closed) return;
    final roomName = _connectionKey(credentials);
    _primary = _createConnection(roomName, credentials).room;
    _transportConnections[_transportKey(transport, matrixRoom.client.userID!)] =
        roomName;
    onProgress?.call('publishing membership');
    await _membership!.start();
    if (_closed) return;
    onProgress?.call('connecting to call server');
    try {
      await _primary!.connect(
        credentials.url.toString(),
        credentials.jwt,
        connectOptions: const lk.ConnectOptions(autoSubscribe: false),
      );
    } catch (_) {
      // WebSocket/HTTP exceptions can contain a URL with an SFU token.
      // Do not pass those details to application copy or diagnostics.
      throw StateError('The call could not connect.');
    }
    if (_closed) return;
    onProgress?.call('publishing microphone');
    await _setMicrophone();
    if (cameraEnabled) {
      try {
        await setCameraEnabled(true);
      } catch (_) {
        cameraEnabled = false;
        error = 'Camera unavailable; joined with audio only.';
      }
    }
    status = VoiceConnectionStatus.connected;
    _started = true;
    _updateSubscriptions();
    await _connectRemoteTransports();
    await _sampleConnectivity();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (matrixRoom.membership != matrix.Membership.join) {
        error = 'You are no longer a member of this room.';
        status = VoiceConnectionStatus.error;
        unawaited(close());
        notifyListeners();
        return;
      }
      unawaited(_sampleConnectivity());
      unawaited(_connectRemoteTransports());
      _applyLocalGate();
      _updateSubscriptions();
    });
    notifyListeners();
  }

  String _connectionKey(RtcTransportCredentials credentials) {
    // Room names can differ between homeservers sharing the same SFU URL.
    // This claim is a deduplication hint, not a substitute for JWT validation
    // by the SFU or Matrix membership validation by this client.
    try {
      final parts = credentials.jwt.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Decode(base64.normalize(parts[1]))),
      );
      final video = payload is Map ? payload['video'] : null;
      final room = video is Map ? video['room'] : null;
      if (room is String && room.length <= 2048) {
        return '${credentials.url}|$room';
      }
    } catch (_) {}
    throw StateError('Invalid MatrixRTC SFU token');
  }

  _SfuConnection _createConnection(
    String key,
    RtcTransportCredentials credentials,
  ) {
    final room = lk.Room(
      roomOptions: lk.RoomOptions(
        encryption: lk.E2EEOptions(keyProvider: _provider!),
        // SeND renders MediaStreams with RTCVideoView, not LiveKit's renderer
        // visibility hooks. Adaptive stream would otherwise pause every video.
        adaptiveStream: false,
        dynacast: true,
        defaultAudioCaptureOptions: lk.AudioCaptureOptions(
          echoCancellation: preferences.echoCancellation,
          noiseSuppression: preferences.noiseSuppression,
          autoGainControl: preferences.autoGainControl,
          deviceId: preferences.preferredAudioInputId.isEmpty
              ? null
              : preferences.preferredAudioInputId,
          stopAudioCaptureOnMute: false,
        ),
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          deviceId: preferences.preferredCameraId.isEmpty
              ? null
              : preferences.preferredCameraId,
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          captureScreenAudio:
              preferences.shareDesktopAudio &&
              (kIsWeb ||
                  (defaultTargetPlatform != TargetPlatform.android &&
                      defaultTargetPlatform != TargetPlatform.iOS)),
          params: lk.VideoParametersPresets.h1080_169,
          maxFrameRate: 30,
        ),
        defaultVideoPublishOptions: const lk.VideoPublishOptions(
          simulcast: true,
        ),
      ),
    );
    final listener = room.createListener()
      ..on<lk.RoomConnectedEvent>((_) => _changed())
      ..on<lk.RoomReconnectingEvent>((_) => _changed())
      ..on<lk.RoomReconnectedEvent>((_) => _changed())
      ..on<lk.RoomDisconnectedEvent>((_) => _changed())
      ..on<lk.ParticipantConnectedEvent>((_) => _changed())
      ..on<lk.ParticipantDisconnectedEvent>((_) => _changed())
      ..on<lk.TrackPublishedEvent>((_) => _changed())
      ..on<lk.TrackSubscribedEvent>((_) => _changed())
      ..on<lk.TrackUnsubscribedEvent>((_) => _changed())
      ..on<lk.TrackMutedEvent>((_) => _changed())
      ..on<lk.TrackUnmutedEvent>((_) => _changed())
      ..on<lk.ActiveSpeakersChangedEvent>((_) => _changed());
    listener.on<lk.TrackE2EEStateEvent>((event) {
      _encryptionStates['$key|${event.participant.identity}:${event.publication.sid}'] =
          event.state;
      if (!_closed) notifyListeners();
    });
    return _connections[key] = _SfuConnection(room, listener);
  }

  void _changed() {
    if (_closed) return;
    _applyLocalGate();
    _updateSubscriptions();
    status = switch (_primary?.connectionState) {
      lk.ConnectionState.connected => VoiceConnectionStatus.connected,
      lk.ConnectionState.reconnecting => VoiceConnectionStatus.reconnecting,
      lk.ConnectionState.disconnected => VoiceConnectionStatus.error,
      _ => VoiceConnectionStatus.connecting,
    };
    notifyListeners();
  }

  Future<void> _installKey(RtcMember member, Uint8List key, int index) async {
    if (_closed || _provider == null) return;
    for (final identity in member.backendIdentities) {
      await _provider!.setRawKey(key, participantId: identity, keyIndex: index);
      if (member.deviceIdentity ==
          '${matrixRoom.client.userID}:${matrixRoom.client.deviceID}') {
        for (final connection in _connections.values) {
          await connection.room.e2eeManager?.setKeyIndex(
            index,
            participantIdentity: identity,
          );
        }
      }
    }
  }

  Future<void> _connectRemoteTransports() async {
    if (_closed || !_started || _connectingRemotes) return;
    _connectingRemotes = true;
    _remoteConnectionDone = Completer<void>();
    try {
      final ownTransportKey = _transportKey(
        transport,
        matrixRoom.client.userID!,
      );
      final needed = <String, (RtcTransport, RtcMember)>{
        ownTransportKey: (transport, _membership!.ownMember),
      };
      for (final member in members) {
        for (final focus in member.transports) {
          needed[_transportKey(focus, member.userId)] = (focus, member);
        }
      }
      for (final entry in needed.entries) {
        if (_closed) break;
        final oldKey = _transportConnections[entry.key];
        final old = _connections[oldKey];
        if (old?.room.connectionState != lk.ConnectionState.disconnected &&
            old != null) {
          continue;
        }
        if (_retryAfter[entry.key]?.isAfter(DateTime.now()) ?? false) continue;
        try {
          final credentials = await api.authorize(
            transport: entry.value.$1,
            roomId: matrixRoom.id,
            memberId: _membership!.memberId,
            publishingUserId: entry.value.$2.userId,
          );
          if (_closed) break;
          final key = _connectionKey(credentials);
          _transportConnections[entry.key] = key;
          if (_connections[key]?.room.connectionState ==
              lk.ConnectionState.disconnected) {
            final stale = _connections.remove(key)!;
            await stale.listener.dispose();
            await stale.room.dispose();
            _encryptionStates.removeWhere(
              (state, _) => state.startsWith('$key|'),
            );
          }
          final connection =
              _connections[key] ?? _createConnection(key, credentials);
          if (entry.key == ownTransportKey) {
            _primary = connection.room;
            if (_microphone != null) {
              try {
                await _microphone!.stop();
                await _microphone!.dispose();
              } catch (_) {}
              _microphone = null;
            }
            screenSharing = false;
          }
          if (connection.room.connectionState ==
              lk.ConnectionState.disconnected) {
            await connection.room.connect(
              credentials.url.toString(),
              credentials.jwt,
              connectOptions: const lk.ConnectOptions(autoSubscribe: false),
            );
          }
          _retryAfter.remove(entry.key);
          if (entry.key == ownTransportKey) {
            await _setMicrophone();
            if (cameraEnabled) await setCameraEnabled(true);
            _changed();
          }
          _updateSubscriptions();
        } catch (e) {
          _retryAfter[entry.key] = DateTime.now().add(
            Duration(
              milliseconds: e is matrix.MatrixException
                  ? e.retryAfterMs ?? 10000
                  : 10000,
            ),
          );
          error =
              'A call server could not be reached. Retrying without disconnecting other participants.';
          notifyListeners();
        }
      }
      // Release SFUs no longer used by any remote member, keeping our publisher.
      final used = {
        for (final id in needed.keys) _transportConnections[id],
        _transportConnections[_transportKey(
          transport,
          matrixRoom.client.userID!,
        )],
      };
      for (final key in _connections.keys.toList()) {
        if (!used.contains(key)) {
          final connection = _connections.remove(key)!;
          await connection.listener.dispose();
          await connection.room.disconnect();
          await connection.room.dispose();
          _encryptionStates.removeWhere(
            (state, _) => state.startsWith('$key|'),
          );
        }
      }
    } finally {
      _connectingRemotes = false;
      _remoteConnectionDone?.complete();
      _remoteConnectionDone = null;
    }
  }

  String _transportKey(RtcTransport focus, String owner) => focus.url == null
      ? focus.id
      : '${focus.id}|${owner.substring(owner.indexOf(':') + 1)}';

  void _updateSubscriptions() {
    for (final connection in _connections.values) {
      for (final participant in connection.room.remoteParticipants.values) {
        final member = _memberForIdentity(participant.identity);
        for (final publication in participant.trackPublications.values) {
          unawaited(
            (member == null
                    ? publication.unsubscribe()
                    : publication.subscribe())
                .catchError((_) {}),
          );
          final track = publication.track;
          if (track is lk.RemoteAudioTrack) {
            final silenced =
                member == null ||
                deafened ||
                locallyMuted.contains(member.userId) ||
                (volumes[member.userId] ?? 1) * preferences.outputVolume <= 0;
            track.mediaStreamTrack.enabled = !silenced;
            if (preferences.preferredAudioOutputId.isNotEmpty) {
              track.setSinkId(preferences.preferredAudioOutputId);
            }
            unawaited(
              setSfuAudioGain(
                track.getCid(),
                track.mediaStreamTrack,
                silenced
                    ? 0
                    : (volumes[member.userId] ?? 1) * preferences.outputVolume,
              ),
            );
          }
        }
      }
    }
  }

  void _applyLocalGate() {
    if (_microphone != null) {
      _microphone!.mediaStreamTrack.enabled =
          !_closed && !_keyPaused && !muted && preferences.microphoneVolume > 0;
    }
    for (final publication
        in _primary?.localParticipant?.trackPublications.values ??
            <lk.LocalTrackPublication>[]) {
      final track = publication.track;
      if (track == null) continue;
      track.mediaStreamTrack.enabled =
          !publication.muted &&
          !_closed &&
          !_keyPaused &&
          (track.source != lk.TrackSource.microphone ||
              (!muted && preferences.microphoneVolume > 0));
    }
  }

  Future<void> _setMicrophone() async {
    final local = _primary?.localParticipant;
    if (local == null || _closed) return;
    if (_microphone == null && !muted) {
      final track = await lk.LocalAudioTrack.create(
        _primary!.roomOptions.defaultAudioCaptureOptions,
      );
      if (_closed) {
        await track.stop();
        await track.dispose();
        return;
      }
      _microphone = track;
      _applyLocalGate();
      await local.publishAudioTrack(track);
    }
    if (_microphone != null) {
      if (muted) {
        await _microphone!.mute();
      } else {
        await _microphone!.unmute();
      }
    }
    _applyLocalGate();
    if (_microphone != null) {
      try {
        await rtc.Helper.setVolume(
          preferences.microphoneVolume,
          _microphone!.mediaStreamTrack,
        );
      } catch (_) {}
    }
  }

  Future<void> setMuted(bool value) async {
    muted = value;
    _applyLocalGate();
    await _setMicrophone();
    if (!_closed) notifyListeners();
  }

  Future<void> setCameraEnabled(bool value) async {
    cameraEnabled = value;
    await _primary?.localParticipant?.setCameraEnabled(value);
    _applyLocalGate();
    if (!_closed) notifyListeners();
  }

  Future<void> setScreenSharing(bool value) async {
    await _primary?.localParticipant?.setScreenShareEnabled(value);
    screenSharing = _primary?.localParticipant?.isScreenShareEnabled() ?? false;
    _applyLocalGate();
    if (!_closed) notifyListeners();
  }

  void applyPreferences(AppPreferences value) {
    preferences = value;
    _applyLocalGate();
    _updateSubscriptions();
    if (_microphone != null) {
      unawaited(
        rtc.Helper.setVolume(
          value.microphoneVolume,
          _microphone!.mediaStreamTrack,
        ).catchError((_) {}),
      );
    }
  }

  void applyRemoteAudio({
    required bool deafen,
    required Set<String> locallyMutedUsers,
    required Map<String, double> participantVolumes,
  }) {
    deafened = deafen;
    locallyMuted = Set.of(locallyMutedUsers);
    volumes = Map.of(participantVolumes);
    _updateSubscriptions();
    if (!_closed) notifyListeners();
  }

  List<RtcMediaStreamSummary> get mediaStreams {
    final result = <RtcMediaStreamSummary>[];
    for (final connection in _connections.values) {
      for (final participant in <lk.Participant>[
        ?connection.room.localParticipant,
        ...connection.room.remoteParticipants.values,
      ]) {
        final local = identical(participant, _primary?.localParticipant);
        final member = local
            ? _membership?.ownMember
            : _memberForIdentity(participant.identity);
        if (member == null) continue;
        for (final pub in participant.videoTrackPublications) {
          final track = pub.track;
          if (track == null) continue;
          result.add(
            RtcMediaStreamSummary(
              id: '${connection.room.name}:${pub.sid}',
              userId: member.userId,
              displayName: matrixRoom
                  .unsafeGetUserFromMemoryOrFallback(member.userId)
                  .calcDisplayname(),
              stream: track.mediaStream,
              local: local,
              screenShare: track.source == lk.TrackSource.screenShareVideo,
              videoMuted: pub.muted,
            ),
          );
        }
      }
    }
    return result;
  }

  Future<void> _sampleConnectivity() async {
    if (_closed) return;
    final required = {
      _transportKey(transport, matrixRoom.client.userID!),
      for (final member in members)
        for (final focus in member.transports)
          _transportKey(focus, member.userId),
    };
    var total = required
        .where((key) => !_transportConnections.containsKey(key))
        .length;
    var connected = 0;
    int? ping;
    for (final connection in _connections.values.toList()) {
      total++;
      if (connection.room.connectionState != lk.ConnectionState.connected) {
        continue;
      }
      connected++;
      // LiveKit 2.13.1 has no public candidate-pair RTT API. Keep this narrow
      // pinned-SDK access diagnostic-only; a stats failure never ends a call.
      for (final pc in [
        // ignore: invalid_use_of_internal_member
        connection.room.engine.publisher?.pc,
        // ignore: invalid_use_of_internal_member
        connection.room.engine.subscriber?.pc,
      ]) {
        if (pc == null) continue;
        try {
          final stats = await pc.getStats().timeout(const Duration(seconds: 2));
          final rtt = rtcPingMilliseconds(
            stats
                .where((r) => r.type == 'candidate-pair')
                .map((r) => Map<String, dynamic>.from(r.values)),
          );
          if (rtt != null && (ping == null || rtt > ping)) ping = rtt;
        } catch (_) {}
      }
    }
    if (_closed) return;
    connectivity = RtcConnectivity(
      state: connected == total && total > 0
          ? RtcConnectivityState.connected
          : connected == 0
          ? RtcConnectivityState.unavailable
          : RtcConnectivityState.waiting,
      connectedPeers: connected,
      totalPeers: total,
      pingMilliseconds: ping,
      detail: 'Connected to $connected of $total call servers',
    );
    notifyListeners();
  }

  Future<void> close() => _closing ??= _close();

  @visibleForTesting
  Future<void> simulateTransportReconnect({bool full = false}) async {
    await _primary?.sendSimulateScenario(
      signalReconnect: !full,
      fullReconnect: full,
    );
  }

  Future<void> _close() async {
    _closed = true;
    _timer?.cancel();
    _applyLocalGate();
    await _membership?.close();
    try {
      await _starting;
    } catch (_) {}
    if (_connectingRemotes) await _remoteConnectionDone?.future;
    for (final connection in _connections.values.toList()) {
      await connection.listener.dispose();
      await connection.room.disconnect();
      await connection.room.dispose();
    }
    _connections.clear();
    _encryptionStates.clear();
    await _provider?.keyProvider.dispose();
    _provider = null;
  }
}
