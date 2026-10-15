import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:matrix/matrix.dart';
import 'rtc_protocol.dart';
import 'rtc_matrix_client.dart';
import 'rtc_room_membership.dart';

typedef RtcMediaKeyReceiver =
    Future<void> Function(RtcMember member, Uint8List key, int index);

/// Matrix owns membership and Olm key distribution. LiveKit never receives
/// media keys. This compatibility publisher uses current Element Call's
/// state format on homeservers without MSC4354 sticky-event support.
class RtcMembershipSession {
  RtcMembershipSession({
    required this.room,
    required this.transport,
    required this.installKey,
    required this.onMembersChanged,
    required this.onError,
    this.onHealthy,
    required this.pauseMedia,
    this.useSticky = false,
    DateTime Function()? clock,
    this.heartbeatTick = const Duration(seconds: 5),
  }) : _clock = clock ?? DateTime.now {
    _created = _clock();
  }
  final DateTime Function() _clock;
  final Duration heartbeatTick;
  final Room room;
  final RtcTransport transport;
  final RtcMediaKeyReceiver installKey;
  final void Function(List<RtcMember>) onMembersChanged;
  final void Function(Object) onError;
  final void Function()? onHealthy;
  final Future<void> Function(bool paused) pauseMedia;
  final bool useSticky;
  final String _stickyId = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  Client get client => room.client;
  String get stateKey =>
      rtcMembershipStateKey(client.userID!, client.deviceID!);
  String get memberId =>
      useSticky ? _stickyId : '${client.userID}:${client.deviceID}';
  late DateTime _created;
  bool _closed = false, _busy = false, _refreshAgain = false;
  bool _published = false, _ready = false;
  bool _leaseHealthy = true, _leaseBusy = false;
  Timer? _heartbeat;
  StreamSubscription<SyncUpdate>? _sync;
  StreamSubscription<ToDeviceEvent>? _keys;
  Completer<void>? _operation;
  Completer<void>? _leaseOperation;
  String? _delayedLeave;
  DateTime? _renewAfter;
  DateTime? _leaseRenewAfter;
  DateTime _lastPublish = DateTime(1970);
  DateTime _lastHeartbeat = DateTime(1970);
  List<RtcMember> members = const [];
  String _membersFingerprint = '';
  Uint8List? _outbound;
  int _keyIndex = -1;
  final _pendingKeys = <ToDeviceEvent>[];

  RtcMember get ownMember => RtcMember(
    userId: client.userID!,
    deviceId: client.deviceID!,
    memberId: memberId,
    createdAt: _created,
    expiresAt: _clock().add(const Duration(minutes: 2)),
    transports: [transport],
  );

  Future<void> start() async {
    if (!client.encryptionEnabled || client.encryption == null) {
      throw StateError(
        'MatrixRTC needs device encryption for media-key sharing',
      );
    }
    _keys = client.onToDeviceEvent.stream.listen((event) {
      if (event.type != rtcEncryptionKeyType || _closed) return;
      // Ignore cleartext keys even if their content looks valid.
      if (event.encryptedContent == null ||
          event.content['room_id'] != room.id) {
        return;
      }
      if (_pendingKeys.length >= 64) _pendingKeys.removeAt(0);
      _pendingKeys.add(event);
      if (_ready) unawaited(refresh());
    });
    try {
      await _rotateKey(const []);
      if (_closed) return;
      await _publish();
      _ready = true;
      _sync = client.onSync.stream.listen((_) => unawaited(refresh()));
      // Lease renewal must not wait for room decryption, device-key queries or
      // Olm delivery. Those can outlast the server's delayed leave reservation.
      _heartbeat = Timer.periodic(heartbeatTick, (_) {
        unawaited(_maintainLease());
        unawaited(refresh());
      });
      await refresh();
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _publish() async {
    if (_delayedLeave != null) {
      try {
        // Give the existing crash-cleanup job a fresh deadline before the
        // state write, rather than letting a slow publication consume it.
        await client
            .manageDelayedEvent(_delayedLeave!, DelayedEventAction.restart)
            .timeout(const Duration(seconds: 10));
        _lastHeartbeat = _clock();
      } on MatrixException catch (error) {
        if (error.errcode != 'M_NOT_FOUND' &&
            error.response?.statusCode != 409) {
          rethrow;
        }
        _delayedLeave = null;
      }
    }
    final now = _clock();
    if (now.difference(_created) > const Duration(hours: 3)) _created = now;
    final lifetime = now.difference(_created) + const Duration(minutes: 2);
    if (useSticky) {
      await _sendSticky(leave: false);
    } else {
      await client
          .setRoomStateWithKey(
            room.id,
            rtcCallMemberType,
            stateKey,
            rtcStateMembership(
              userId: client.userID!,
              deviceId: client.deviceID!,
              createdAt: _created,
              transport: transport,
              lifetime: lifetime,
            ),
          )
          .timeout(const Duration(seconds: 15));
    }
    _published = true;
    _lastPublish = now;
    // Some deployed homeservers retain an old delayed state write after an
    // immediate update. Keep renewing that job rather than abandoning it and
    // scheduling a second leave which the old one could later overwrite.
    await _scheduleLeave();
  }

  Future<void> _scheduleLeave() async {
    if (_delayedLeave != null) return;
    try {
      if (useSticky) {
        _delayedLeave = await _sendSticky(leave: true, delayed: true);
        return;
      }
      _delayedLeave = await client
          .setRoomStateWithKeyWithDelay(
            room.id,
            rtcCallMemberType,
            stateKey,
            20000,
            {},
          )
          .timeout(const Duration(seconds: 10));
    } on MatrixException catch (e) {
      if (e.errcode != 'M_UNRECOGNIZED' && e.response?.statusCode != 404) {
        rethrow;
      }
      // Expiring membership remains the crash fallback on older homeservers.
    }
  }

  Future<String> _sendSticky({
    required bool leave,
    bool delayed = false,
  }) async {
    final content = rtcStickyMembership(
      userId: client.userID!,
      deviceId: client.deviceID!,
      memberId: memberId,
      transport: transport,
      leave: leave,
    );
    final wire = room.encrypted
        ? await client.encryption!.encryptGroupMessagePayload(
            room.id,
            content,
            type: rtcStickyMemberType,
          )
        : content;
    if (room.encrypted && !wire.containsKey('ciphertext')) {
      throw StateError('Unable to encrypt MatrixRTC membership');
    }
    final type = wire.containsKey('ciphertext')
        ? EventTypes.Encrypted
        : rtcStickyMemberType;
    final result = await client
        .request(
          RequestType.PUT,
          '/client/v3/rooms/${Uri.encodeComponent(room.id)}/send/${Uri.encodeComponent(type)}/${client.generateUniqueTransactionId()}',
          data: wire,
          query: {
            'org.matrix.msc4354.sticky_duration_ms': '120000',
            if (delayed) 'org.matrix.msc4140.delay': '20000',
          },
        )
        .timeout(const Duration(seconds: 15));
    final id = result[delayed ? 'delay_id' : 'event_id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Invalid MatrixRTC membership response');
    }
    return id;
  }

  Future<List<RtcMember>> _stickyMembers() async {
    final rtcClient = client;
    if (rtcClient is! RtcMatrixClient) return const [];
    return (await rtcClient.hydrateRtcMembers(room))
        .where((member) => member.deviceIdentity != ownMember.deviceIdentity)
        .toList();
  }

  Future<void> refresh() async {
    if (_closed) return;
    if (_busy) {
      _refreshAgain = true;
      return;
    }
    if (_renewAfter != null && _clock().isBefore(_renewAfter!)) return;
    _busy = true;
    _operation = Completer<void>();
    try {
      await _maintainLease();
      if (!_leaseHealthy || _closed) return;
      final next = List<RtcMember>.of(await _stickyMembers());
      final rtcClient = client;
      if (rtcClient is RtcMatrixClient) {
        for (final member in rtcClient.rtcStateMembers(room.id)) {
          if (member.deviceIdentity != ownMember.deviceIdentity &&
              !next.any((m) => m.deviceIdentity == member.deviceIdentity)) {
            next.add(member);
          }
        }
      }
      final now = _clock();
      for (final event in room.states[rtcCallMemberType]?.values ?? <Event>[]) {
        final member = RtcMember.parse(
          type: event.type,
          sender: event.senderId,
          content: event.content,
          stateKey: event.stateKey,
          timestamp: event is Event ? event.originServerTs : DateTime(1970),
          now: now,
        );
        if (member != null &&
            member.deviceIdentity != ownMember.deviceIdentity &&
            !next.any((m) => m.deviceIdentity == member.deviceIdentity)) {
          next.add(member);
        }
        if (next.length >= 512) break;
      }
      next.removeWhere((member) => !rtcUserStillJoined(room, member.userId));
      next.sort((a, b) => a.deviceIdentity.compareTo(b.deviceIdentity));
      final fingerprint = jsonEncode(
        next
            .map(
              (m) => [
                m.deviceIdentity,
                m.memberId,
                m.createdAt.millisecondsSinceEpoch,
                m.transports.map((t) => t.toJson()).toList(),
              ],
            )
            .toList(),
      );
      members = next;
      if (fingerprint != _membersFingerprint) {
        await _rotateKey(next);
        _membersFingerprint = fingerprint;
        if (!_closed) onMembersChanged(List.unmodifiable(next));
      }
      await _receiveKeys();
      await pauseMedia(!_leaseHealthy);
      _renewAfter = null;
      if (_leaseHealthy && !_closed) onHealthy?.call();
    } catch (error) {
      await pauseMedia(true);
      _renewAfter = _clock().add(
        Duration(
          milliseconds: error is MatrixException
              ? error.retryAfterMs ?? 5000
              : 5000,
        ),
      );
      if (!_closed) onError(error);
    } finally {
      _busy = false;
      _operation?.complete();
      _operation = null;
      if (_refreshAgain && !_closed) {
        _refreshAgain = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> _maintainLease() async {
    if (_closed) return;
    if (_leaseBusy) {
      await _leaseOperation?.future;
      return;
    }
    if (_leaseRenewAfter != null && _clock().isBefore(_leaseRenewAfter!)) {
      return;
    }
    _leaseBusy = true;
    _leaseOperation = Completer<void>();
    try {
      if (_published &&
          _clock().difference(_lastPublish) >= const Duration(seconds: 45)) {
        await _publish();
      } else if (_delayedLeave != null &&
          _clock().difference(_lastHeartbeat) >= const Duration(seconds: 5)) {
        try {
          await client
              .manageDelayedEvent(_delayedLeave!, DelayedEventAction.restart)
              .timeout(const Duration(seconds: 10));
          _lastHeartbeat = _clock();
        } on MatrixException catch (e) {
          if (e.errcode != 'M_NOT_FOUND' && e.response?.statusCode != 409) {
            rethrow;
          }
          // The delayed leave may already have fired. Restore membership and
          // its leave reservation together, not only the heartbeat timer.
          _delayedLeave = null;
          await _publish();
        }
      }
      _leaseHealthy = true;
      _leaseRenewAfter = null;
    } catch (error) {
      await pauseMedia(true);
      _leaseHealthy = false;
      _leaseRenewAfter = _clock().add(
        Duration(
          milliseconds: error is MatrixException
              ? error.retryAfterMs ?? 5000
              : 5000,
        ),
      );
      if (!_closed) onError(error);
    } finally {
      _leaseBusy = false;
      _leaseOperation?.complete();
      _leaseOperation = null;
    }
  }

  Future<void> _rotateKey(List<RtcMember> recipients) async {
    await pauseMedia(true);
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final index = (_keyIndex + 1) % 256;
    if (recipients.isNotEmpty) {
      await client
          .updateUserDeviceKeys(
            additionalUsers: recipients.map((m) => m.userId).toSet(),
          )
          .timeout(const Duration(seconds: 15));
      final devices = <DeviceKeys>[];
      for (final member in recipients) {
        if (!rtcUserStillJoined(room, member.userId)) continue;
        final device =
            client.userDeviceKeys[member.userId]?.deviceKeys[member.deviceId];
        if (device == null || device.blocked) continue;
        devices.add(device);
      }
      if (devices.isNotEmpty) {
        await client
            .sendToDeviceEncrypted(devices, rtcEncryptionKeyType, {
              'room_id': room.id,
              'member_id': memberId,
              'member': {'id': memberId, 'claimed_device_id': client.deviceID},
              'media_key': {
                'index': index,
                'key': base64Encode(key).replaceAll('=', ''),
              },
              'keys': {
                'index': index,
                'key': base64Encode(key).replaceAll('=', ''),
              },
            })
            .timeout(const Duration(seconds: 15));
      }
      // Give recipients time to install the key before switching encryption.
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (_closed) {
      key.fillRange(0, key.length, 0);
      return;
    }
    await installKey(ownMember, key, index);
    _outbound?.fillRange(0, _outbound!.length, 0);
    _outbound = key;
    _keyIndex = index;
    await pauseMedia(!_leaseHealthy);
  }

  Future<void> _receiveKeys() async {
    for (final event in _pendingKeys.toList()) {
      final memberData = event.content['member'];
      final claimedDevice = memberData is Map
          ? memberData['claimed_device_id']
          : null;
      final id =
          event.content['member_id'] ??
          (memberData is Map ? memberData['id'] : null);
      final member = members
          .where(
            (m) =>
                m.userId == event.senderId &&
                m.deviceId == claimedDevice &&
                m.memberId == id,
          )
          .firstOrNull;
      if (member == null) continue;
      _pendingKeys.remove(event);
      final device =
          client.userDeviceKeys[member.userId]?.deviceKeys[member.deviceId];
      if (device == null ||
          device.blocked ||
          event.encryptedContent?['sender_key'] != device.curve25519Key) {
        continue;
      }
      final mediaKey = event.content['media_key'] ?? event.content['keys'];
      if (mediaKey is! Map) continue;
      final index = mediaKey['index'], encoded = mediaKey['key'];
      if (index is! int ||
          index < 0 ||
          index > 255 ||
          encoded is! String ||
          encoded.length > 128) {
        continue;
      }
      try {
        final key = base64Decode(base64.normalize(encoded));
        if (key.length < 16 || key.length > 64) continue;
        await installKey(member, key, index);
      } on FormatException {
        // Malformed or oversized remote keys must not tear down the call.
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    await _sync?.cancel();
    await _keys?.cancel();
    if (_leaseBusy) await _leaseOperation?.future;
    if (_busy) await _operation?.future;
    var leaveSent = false;
    try {
      if (_delayedLeave != null) {
        await client
            .manageDelayedEvent(_delayedLeave!, DelayedEventAction.send)
            .timeout(const Duration(seconds: 5));
        leaveSent = true;
      }
    } catch (_) {
      // It may have been cancelled by a state update or already sent.
    }
    if (_published && !leaveSent) {
      try {
        if (useSticky) {
          await _sendSticky(leave: true);
        } else {
          await client
              .setRoomStateWithKey(room.id, rtcCallMemberType, stateKey, {})
              .timeout(const Duration(seconds: 5));
        }
      } catch (_) {
        // Keep any still-pending crash reservation if the explicit leave
        // fails too. Expiring membership is the final offline fallback.
      }
    }
    _pendingKeys.clear();
    _outbound?.fillRange(0, _outbound!.length, 0);
    _outbound = null;
  }
}
