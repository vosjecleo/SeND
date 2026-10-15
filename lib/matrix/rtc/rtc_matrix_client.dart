import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'rtc_protocol.dart';

class RtcStickyEvent {
  const RtcStickyEvent(this.json, this.expiresAt, this.size);
  final Map<String, Object?> json;
  final DateTime expiresAt;
  final int size;
}

/// Preserve MSC4354 additions before matrix-dart's typed sync parser drops
/// them. There is still exactly one SDK sync loop and one presence policy.
/// These events are transient RTC metadata, never a second session store.
class RtcMatrixClient extends Client {
  RtcMatrixClient(
    super.clientName, {
    required super.database,
    super.customVideoThumbnailGenerator,
    super.importantStateEvents,
    super.shareKeysWith,
    super.httpClient,
    super.logLevel,
  });
  final _sticky = <String, Map<String, RtcStickyEvent>>{};
  final _resolved = <String, Map<String, (Event, DateTime)>>{};
  final _decoded = <String, Event>{};
  final _state = <String, Map<String, Map<String, Object?>>>{};
  final _hydrating = <String, Future<List<RtcMember>>>{};
  bool _disposedRtc = false;
  List<RtcMember> rtcStateMembers(String roomId) =>
      (_state[roomId]?.values ?? <Map<String, Object?>>[])
          .map(
            (event) => RtcMember.parse(
              type: rtcCallMemberType,
              sender: event['sender'] as String,
              content: event['content'],
              stateKey: event['state_key'] as String?,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                event['origin_server_ts'] is int
                    ? event['origin_server_ts'] as int
                    : 0,
              ),
            ),
          )
          .whereType<RtcMember>()
          .toList();
  Iterable<String> get rtcStickyRoomIds => _sticky.keys.toList();
  List<RtcMember> cachedRtcMembers(String roomId) {
    final now = DateTime.now();
    return (_resolved[roomId]?.values ?? <(Event, DateTime)>[])
        .map(
          (record) => RtcMember.parse(
            type: record.$1.type,
            sender: record.$1.senderId,
            content: record.$1.content,
            timestamp: record.$1.originServerTs,
            stickyExpiresAt: record.$2,
            now: now,
          ),
        )
        .whereType<RtcMember>()
        .toList();
  }

  Future<List<RtcMember>> hydrateRtcMembers(Room room) =>
      _hydrating.putIfAbsent(
        room.id,
        () => _hydrateRtcMembers(room).whenComplete(() {
          _hydrating.remove(room.id);
        }),
      );

  Future<List<RtcMember>> _hydrateRtcMembers(Room room) async {
    if (_disposedRtc) return const [];
    final records = rtcStickyEvents(room.id);
    final winners = _resolved.putIfAbsent(room.id, () => {});
    for (final record in records) {
      final id = record.json['event_id'] as String;
      var event = _decoded[id] ?? Event.fromJson(record.json, room);
      if (event.type == EventTypes.Encrypted && encryption != null) {
        event = await encryption!.decryptRoomEvent(event);
      }
      if (_disposedRtc) return const [];
      if (![rtcStickyMemberType, 'm.rtc.member'].contains(event.type)) continue;
      _decoded[id] = event;
      final member = event.content['member'];
      final key =
          event.content['msc4354_sticky_key'] ?? event.content['sticky_key'];
      if (event.content['slot_id'] != rtcRoomSlot ||
          member is! Map ||
          key is! String ||
          key != member['id']) {
        continue;
      }
      final index = '${event.senderId}|$key';
      final old = winners[index];
      if (old == null ||
          event.originServerTs.isAfter(old.$1.originServerTs) ||
          (event.originServerTs == old.$1.originServerTs &&
              event.eventId.compareTo(old.$1.eventId) > 0)) {
        winners[index] = (event, record.expiresAt);
      }
    }
    while (winners.length > 2048) {
      winners.remove(winners.keys.first);
    }
    return cachedRtcMembers(room.id);
  }

  List<RtcStickyEvent> rtcStickyEvents(String roomId) {
    _pruneSticky();
    return _sticky[roomId]?.values.toList() ?? const [];
  }

  @override
  Future<SyncUpdate> sync({
    String? filter,
    String? since,
    bool? fullState,
    PresenceType? setPresence,
    int? timeout,
    bool? useStateAfter,
  }) async {
    // Keep the SDK's request, authentication and sync cursor unchanged. Only
    // retain RTC extensions which its current typed response does not expose.
    final uri = baseUri!.resolveUri(
      Uri(
        path: '_matrix/client/v3/sync',
        queryParameters: {
          'filter': ?filter,
          'since': ?since,
          if (fullState != null) 'full_state': fullState.toString(),
          if (setPresence != null) 'set_presence': setPresence.name,
          if (timeout != null) 'timeout': timeout.toString(),
          if (useStateAfter != null)
            'use_state_after': useStateAfter.toString(),
        },
      ),
    );
    final request = http.Request('GET', uri)
      ..headers['authorization'] = 'Bearer ${bearerToken!}';
    final response = await httpClient.send(request);
    final bytes = await response.stream.toBytes();
    if (response.statusCode != 200) unexpectedResponse(response, bytes);
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    retainRtcExtensions(value);
    return SyncUpdate.fromJson(value);
  }

  void retainRtcExtensions(Map<String, Object?> value, {DateTime? receivedAt}) {
    final now = receivedAt ?? DateTime.now();
    _pruneSticky(now: now);
    final rooms = value['rooms'];
    final joins = rooms is Map ? rooms['join'] : null;
    for (final entry in (joins is Map ? joins : const {}).entries.take(256)) {
      if (entry.key is! String || entry.value is! Map) continue;
      final data = entry.value as Map;
      for (final sectionName in [
        'state',
        'msc4354_sticky',
        'sticky',
        'timeline',
        'state_after',
      ]) {
        final section = data[sectionName];
        final events = section is Map ? section['events'] : null;
        if (events is! List) continue;
        for (final event in events.take(512)) {
          if (event is Map &&
              event['type'] == rtcCallMemberType &&
              event['state_key'] is String &&
              event['sender'] is String) {
            final cache = _state.putIfAbsent(entry.key, () => {});
            if (utf8.encode(jsonEncode(event)).length > 32768) {
              cache.remove(event['state_key']);
              continue;
            }
            cache[event['state_key']] = Map<String, Object?>.from(event);
            while (cache.length > 512) {
              cache.remove(cache.keys.first);
            }
            continue;
          }
          if (event is! Map ||
              ![
                rtcStickyMemberType,
                'm.rtc.member',
                EventTypes.Encrypted,
              ].contains(event['type'])) {
            continue;
          }
          final unsigned = event['unsigned'];
          final ttl = unsigned is Map
              ? unsigned['msc4354_sticky_duration_ttl_ms'] ??
                    unsigned['sticky_duration_remaining_ms']
              : null;
          final id = event['event_id'];
          if (ttl is! int ||
              ttl <= 0 ||
              ttl > 3600000 ||
              id is! String ||
              id.length > 255) {
            continue;
          }
          final size = utf8.encode(jsonEncode(event)).length;
          if (size > 32768) continue;
          final cache = _sticky.putIfAbsent(entry.key, () => {});
          final expires = now.add(Duration(milliseconds: ttl));
          final old = cache[id];
          // Re-delivery must never extend the authoritative sticky expiry.
          cache[id] = RtcStickyEvent(
            Map<String, Object?>.from(event),
            old != null && old.expiresAt.isBefore(expires)
                ? old.expiresAt
                : expires,
            size,
          );
        }
      }
    }
    final leaves = rooms is Map ? rooms['leave'] : null;
    if (leaves is Map) {
      for (final room in leaves.keys) {
        _state.remove(room);
        _sticky.remove(room);
        _resolved.remove(room);
      }
    }
    while (_state.length > 128) {
      _state.remove(_state.keys.first);
    }
    var stateCount = _state.values.fold(0, (n, room) => n + room.length);
    var stateBytes = _state.values
        .expand((room) => room.values)
        .fold(0, (n, event) => n + utf8.encode(jsonEncode(event)).length);
    _state.removeWhere((_, room) => room.isEmpty);
    while ((stateCount > 1024 || stateBytes > 4 * 1024 * 1024) &&
        _state.isNotEmpty) {
      final first = _state.values.first;
      stateBytes -= utf8
          .encode(jsonEncode(first.remove(first.keys.first)))
          .length;
      stateCount--;
      _state.removeWhere((_, room) => room.isEmpty);
    }
    // Hard bound: at most 1024 transient events across all rooms. RTC events
    // are normally small; retaining arbitrary sticky application payloads is
    // not part of this bridge's job.
    var count = _sticky.values.fold(0, (n, room) => n + room.length);
    var bytes = _sticky.values
        .expand((room) => room.values)
        .fold(0, (n, event) => n + event.size);
    while ((count > 1024 || bytes > 4 * 1024 * 1024) && _sticky.isNotEmpty) {
      final first = _sticky.values.first;
      bytes -= first.remove(first.keys.first)!.size;
      count--;
      _sticky.removeWhere((_, room) => room.isEmpty);
    }
  }

  void _pruneSticky({DateTime? now}) {
    final current = now ?? DateTime.now();
    for (final room in _sticky.values) {
      room.removeWhere((_, event) => !event.expiresAt.isAfter(current));
    }
    _sticky.removeWhere((_, room) => room.isEmpty);
    final retained = _sticky.values.expand((room) => room.keys).toSet();
    _decoded.removeWhere((id, _) => !retained.contains(id));
    for (final room in _resolved.values) {
      room.removeWhere(
        (_, record) => current.difference(record.$2) > const Duration(hours: 1),
      );
    }
    _resolved.removeWhere(
      (id, room) => room.isEmpty && !_hydrating.containsKey(id),
    );
  }

  @override
  Future<void> dispose({bool closeDatabase = true}) async {
    _disposedRtc = true;
    _sticky.clear();
    _resolved.clear();
    _decoded.clear();
    _state.clear();
    await super.dispose(closeDatabase: closeDatabase);
  }
}
