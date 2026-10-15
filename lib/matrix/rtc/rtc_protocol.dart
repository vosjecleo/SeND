import 'dart:convert';
import 'package:crypto/crypto.dart';

const rtcCallMemberType = 'org.matrix.msc3401.call.member';
const rtcStickyMemberType = 'org.matrix.msc4143.rtc.member';
const rtcEncryptionKeyType = 'io.element.call.encryption_keys';
const rtcRoomSlot = 'm.call#ROOM';

Uri? rtcSecureUrl(Object? raw, {bool websocket = false}) {
  if (raw is! String || raw.length > 2048) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != (websocket ? 'wss' : 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri;
}

/// MSC4195's current, transitional and standalone-service transport formats.
class RtcTransport {
  const RtcTransport({this.url, this.serviceUrl});
  final Uri? url, serviceUrl;
  String get id => url?.toString() ?? serviceUrl!.toString();
  Map<String, Object> toJson() => {
    'type': 'livekit',
    if (url != null) 'url': url.toString(),
    if (serviceUrl != null) 'livekit_service_url': serviceUrl.toString(),
  };

  static RtcTransport? fromJson(Object? value) {
    if (value is! Map || !['livekit', 'm.livekit'].contains(value['type'])) {
      return null;
    }
    final url = rtcSecureUrl(value['url'], websocket: true);
    final service = rtcSecureUrl(value['livekit_service_url']);
    // Reject malformed optional URLs too, not just malformed required URLs.
    if ((value.containsKey('url') && url == null) ||
        (value.containsKey('livekit_service_url') && service == null) ||
        (url == null && service == null)) {
      return null;
    }
    return RtcTransport(url: url, serviceUrl: service);
  }

  static List<RtcTransport> fromResponse(Object? value) {
    if (value is! Map) return const [];
    final list =
        value['transports'] ??
        value['rtc_transports'] ??
        value['org.matrix.msc4143.rtc_foci'];
    if (list is! List) return const [];
    return list.take(8).map(fromJson).whereType<RtcTransport>().toList();
  }
}

/// MatrixRTC member identity, independent of the number of SFU connections.
class RtcMember {
  const RtcMember({
    required this.userId,
    required this.deviceId,
    required this.memberId,
    required this.createdAt,
    required this.expiresAt,
    required this.transports,
  });
  final String userId, deviceId, memberId;
  final DateTime createdAt, expiresAt;
  final List<RtcTransport> transports;
  String get deviceIdentity => '$userId:$deviceId';
  String get hashedIdentity => rtcHashedIdentity(userId, memberId);
  List<String> get backendIdentities => [
    if (transports.any((t) => t.url != null)) hashedIdentity,
    if (transports.any((t) => t.serviceUrl != null)) deviceIdentity,
  ];

  /// Read deployed Element Call state events and MSC4143 sticky memberships.
  /// Sticky callers must supply the server's absolute sticky expiry.
  static RtcMember? parse({
    required String type,
    required String sender,
    required Object? content,
    required DateTime timestamp,
    String? stateKey,
    DateTime? stickyExpiresAt,
    DateTime? now,
  }) {
    if (content is! Map ||
        !RegExp(r'^@[^\s:]+:[^\s]+$').hasMatch(sender) ||
        sender.length > 255) {
      return null;
    }
    final current = now ?? DateTime.now();
    String? device, memberId;
    DateTime created = timestamp, expiry;
    Object? rawTransports;
    if (type == rtcCallMemberType) {
      if (content['application'] != 'm.call' ||
          content['scope'] != 'm.room' ||
          !['', 'ROOM'].contains(content['call_id'])) {
        return null;
      }
      device = content['device_id'] is String ? content['device_id'] : null;
      // A sender cannot claim another user's state slot, even if a permissive
      // room lets them write it. Older Element Call slots lack the app suffix.
      if (device == null ||
          ![
            rtcMembershipStateKey(sender, device),
            '_${sender}_$device',
            '${sender}_$device',
          ].contains(stateKey)) {
        return null;
      }
      memberId = content['membershipID'] is String
          ? content['membershipID']
          : '$sender:$device';
      final createdTs = content['created_ts'];
      if (createdTs is int && createdTs > 0) {
        created = DateTime.fromMillisecondsSinceEpoch(createdTs);
      }
      final duration = content['expires'];
      if (duration is! int || duration <= 0 || duration > 14400000) return null;
      expiry = created.add(Duration(milliseconds: duration));
      rawTransports = content['foci_preferred'];
    } else if (type == rtcStickyMemberType || type == 'm.rtc.member') {
      final member = content['member'];
      if (content['slot_id'] != rtcRoomSlot ||
          member is! Map ||
          member['membership'] != 'join' ||
          member['user_id'] != sender ||
          stickyExpiresAt == null) {
        return null;
      }
      device = member['device_id'] is String ? member['device_id'] : null;
      memberId = member['id'] is String ? member['id'] : null;
      expiry = stickyExpiresAt;
      final transports = content['transports'];
      rawTransports = transports is Map ? transports['published'] : null;
    } else {
      return null;
    }
    if (device == null ||
        device.isEmpty ||
        device.length > 255 ||
        memberId == null ||
        memberId.isEmpty ||
        memberId.length > 255 ||
        !expiry.isAfter(current) ||
        created.isAfter(current.add(const Duration(minutes: 5))) ||
        rawTransports is! List) {
      return null;
    }
    final transports = rawTransports
        .take(8)
        .map(RtcTransport.fromJson)
        .whereType<RtcTransport>()
        .toList();
    if (transports.isEmpty) return null;
    return RtcMember(
      userId: sender,
      deviceId: device,
      memberId: memberId,
      createdAt: created,
      expiresAt: expiry,
      transports: transports,
    );
  }
}

String rtcHashedIdentity(String userId, String memberId) => base64Encode(
  sha256.convert(utf8.encode(jsonEncode([userId, memberId]))).bytes,
).replaceAll('=', '');

String rtcMembershipStateKey(String userId, String deviceId) =>
    '_${userId}_${deviceId}_m.call';

Map<String, dynamic> rtcStickyMembership({
  required String userId,
  required String deviceId,
  required String memberId,
  required RtcTransport transport,
  bool leave = false,
}) => {
  'slot_id': rtcRoomSlot,
  'msc4354_sticky_key': memberId,
  'member': {
    'id': memberId,
    'membership': leave ? 'leave' : 'join',
    if (!leave) 'user_id': userId,
    if (!leave) 'device_id': deviceId,
  },
  if (!leave) 'application': {'type': 'm.call', 'm.call.intent': 'audio'},
  if (!leave)
    'transports': {
      'published': [transport.toJson()],
      'can_subscribe': ['livekit'],
    },
};

Map<String, Object> rtcStateMembership({
  required String userId,
  required String deviceId,
  required DateTime createdAt,
  required RtcTransport transport,
  Duration lifetime = const Duration(minutes: 2),
}) => {
  'application': 'm.call',
  'call_id': '',
  'scope': 'm.room',
  'device_id': deviceId,
  'membershipID': '$userId:$deviceId',
  'created_ts': createdAt.millisecondsSinceEpoch,
  'expires': lifetime.inMilliseconds,
  'm.call.intent': 'audio',
  'focus_active': {'type': 'livekit', 'focus_selection': 'multi_sfu'},
  'foci_preferred': [transport.toJson()],
};
