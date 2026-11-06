import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';
import 'package:collection/collection.dart';
import '../models/space_administration.dart' show SpaceJoinResult;

const spacePreferencesType = 'net.send.space_preferences.v1';
const _mutePrefix = 'net.send.space.mute.';

/// Owns opt-in room membership and independent space-wide notification rules.
/// It never changes a room's access, encryption or existing notification rule.
class SpaceFollowController {
  SpaceFollowController({required this.client, required this.changed}) {
    _readPreferences();
  }
  final Client client;
  final void Function() changed;
  Map<String, dynamic> _preferences = {};
  Map<String, dynamic>? _pending;
  Future<void> _writes = Future<void>.value();
  StreamSubscription<SyncUpdate>? _sync;
  Timer? _timer;
  bool _active = true, _running = false, _rulesRunning = false;
  bool _reconcileAgain = false;
  bool _rulesAgain = false;
  Future<void>? _ruleRequest;
  final _signatures = <String, String>{};
  final _lastChecked = <String, DateTime>{};
  final _inFlight = <String, Future<SpaceJoinResult>>{};
  final _attempted = <String>{};
  final _installed = <String>{};
  final _rulesChecked = <String>{};
  final _lastResults = <String, SpaceJoinResult>{};
  final _pendingRecommendations = <String, String>{};
  final _appliedRecommendations = <String>{};
  final _recommendationAttempts = <String, DateTime>{};
  final _departingSpaces = <String>{};
  Set<String> _excluded(String spaceId) =>
      (_entry(spaceId)['excluded_channels'] is List
              ? (_entry(spaceId)['excluded_channels'] as List)
                    .whereType<String>()
              : const <String>[])
          .toSet();

  Map<dynamic, dynamic> _entry(String id) =>
      _preferences[id] is Map ? _preferences[id] as Map : const {};
  bool autoJoin(String id) => _entry(id)['auto_join'] != false;
  bool muted(String id) =>
      (_entry(id)['muted'] is bool ? _entry(id)['muted'] as bool : null) ??
      (client.getRoomById(id)?.pushRuleState == PushRuleState.dontNotify);
  SpaceJoinResult? result(String id) => _lastResults[id];

  bool roomMuted(String roomId) => client.rooms.any(
    (space) =>
        space.isSpace &&
        space.membership == Membership.join &&
        muted(space.id) &&
        space.spaceChildren.any((child) => child.roomId == roomId),
  );

  void start() {
    if (_sync != null || !_active) return;
    _sync = client.onSync.stream.listen((_) {
      _readPreferences();
      _schedule();
    });
    _schedule();
  }

  void _readPreferences() {
    final content = client.accountData[spacePreferencesType]?.content;
    final incoming = content == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(content);
    if (_pending != null &&
        !const DeepCollectionEquality().equals(incoming, _pending)) {
      return;
    }
    _pending = null;
    _preferences = incoming;
  }

  Future<void> _set(String id, String key, Object value) {
    final task = _writes.catchError((Object _) {}).then((_) async {
      if (!_active) return;
      final previous = _preferences;
      final next = <String, dynamic>{
        ...previous,
        id: {..._entry(id), key: value},
      };
      _preferences = next;
      _pending = next;
      changed();
      try {
        await client.setAccountData(client.userID!, spacePreferencesType, next);
      } catch (_) {
        if (_active && identical(_preferences, next)) {
          _preferences = previous;
          _pending = null;
          changed();
        }
        rethrow;
      }
    });
    _writes = task;
    return task;
  }

  Future<void> setAutoJoin(String id, bool value) async {
    await _set(id, 'auto_join', value);
    _signatures.remove(id);
    if (value && _active) {
      _attempted.removeWhere((attempt) => attempt.startsWith('$id|'));
      unawaited(joinAvailable(id).then<void>((_) {}, onError: (Object _) {}));
    }
  }

  Future<void> setMuted(String id, bool value) async {
    await _set(id, 'muted', value);
    if (!_active) return;
    try {
      await client
          .getRoomById(id)
          ?.setPushRuleState(
            value ? PushRuleState.dontNotify : PushRuleState.notify,
          );
    } finally {
      await _syncMuteRules();
      if (_active) changed();
    }
  }

  void _schedule() {
    if (_timer?.isActive == true) return;
    _timer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_reconcile()),
    );
  }

  Future<void> _reconcile() async {
    if (!_active) return;
    if (_running) {
      _reconcileAgain = true;
      return;
    }
    _running = true;
    try {
      for (final space
          in client.rooms
              .where((r) => r.isSpace && r.membership == Membership.join)
              .toList()) {
        if (!_active) return;
        if (_departingSpaces.contains(space.id)) continue;
        final signature = jsonEncode([
          autoJoin(space.id),
          muted(space.id),
          for (final child in space.spaceChildren)
            [
              child.roomId,
              client.getRoomById(child.roomId ?? '')?.membership.name,
            ],
        ]);
        final needsRetry =
            space.spaceChildren.any(
              (child) =>
                  client.getRoomById(child.roomId ?? '')?.membership !=
                  Membership.join,
            ) &&
            DateTime.now().difference(
                  _lastChecked[space.id] ?? DateTime(1970),
                ) >=
                const Duration(minutes: 2);
        if (_signatures[space.id] == signature && !needsRetry) continue;
        _signatures[space.id] = signature;
        if (needsRetry) {
          _attempted.removeWhere(
            (attempt) => attempt.startsWith('${space.id}|'),
          );
        }
        _lastChecked[space.id] = DateTime.now();
        if (autoJoin(space.id)) await joinAvailable(space.id);
      }
      for (final entry in _pendingRecommendations.entries.toList()) {
        if (!_active) return;
        if (DateTime.now().difference(
              _recommendationAttempts[entry.key] ?? DateTime(1970),
            ) <
            const Duration(minutes: 1)) {
          continue;
        }
        try {
          await channelJoined(entry.value, entry.key);
        } catch (_) {
          /* Retain for reconnect. */
        }
      }
      await _syncMuteRules();
    } catch (_) {
      // Explicit catch-up and notification controls expose retryable failures.
    } finally {
      _running = false;
      if (_active && _reconcileAgain) {
        _reconcileAgain = false;
        _schedule();
      }
    }
  }

  Future<SpaceJoinResult> joinAvailable(String id, {bool force = false}) =>
      _inFlight[id] ??= _joinAvailable(id, force: force).whenComplete(() {
        _inFlight.remove(id);
      });

  Future<SpaceJoinResult> _joinAvailable(
    String id, {
    required bool force,
  }) async {
    final space = client.getRoomById(id);
    if (!_active ||
        _departingSpaces.contains(id) ||
        space == null ||
        !space.isSpace ||
        space.membership != Membership.join) {
      return const SpaceJoinResult();
    }
    var joined = 0, failed = 0;
    String? cursor;
    final seen = <String>{};
    final cursors = <String>{};
    try {
      do {
        final page = await client
            .getSpaceHierarchy(id, maxDepth: 1, limit: 100, from: cursor)
            .timeout(const Duration(seconds: 20));
        if (!_active) break;
        for (final item in page.rooms) {
          if (!_active ||
              _departingSpaces.contains(id) ||
              (!force && !autoJoin(id))) {
            break;
          }
          if (item.roomId == id ||
              item.roomType == 'm.space' ||
              !seen.add(item.roomId)) {
            continue;
          }
          final room = client.getRoomById(item.roomId);
          if (!force && _excluded(id).contains(item.roomId)) continue;
          if (room?.membership == Membership.join) continue;
          if (!{
                'public',
                'restricted',
                'knock_restricted',
              }.contains(item.joinRule) &&
              room?.membership != Membership.invite) {
            continue;
          }
          final attempt =
              '$id|${item.roomId}|${item.joinRule}|${room?.membership.name}';
          if (!force && !_attempted.add(attempt)) continue;
          _attempted.add(attempt);
          try {
            if (!_active || (!force && !autoJoin(id))) break;
            final via =
                (space
                                .getState(EventTypes.SpaceChild, item.roomId)
                                ?.content['via']
                            as List? ??
                        const [])
                    .whereType<String>()
                    .where((server) => server.isNotEmpty)
                    .take(3)
                    .toList();
            await _joinRoom(item.roomId, via: via.isEmpty ? null : via);
            if (!_active) break;
            final joinedRoom = client.getRoomById(item.roomId);
            if (joinedRoom == null ||
                joinedRoom.membership != Membership.join) {
              continue;
            }
            joined++;
            await channelJoined(space.id, joinedRoom.id);
            if (_active) changed();
          } catch (_) {
            failed++;
          }
        }
        cursor = page.nextBatch;
      } while (_active && cursor != null && cursors.add(cursor));
    } catch (_) {
      failed++;
    }
    final result = SpaceJoinResult(joined: joined, failed: failed);
    if (_active) {
      _lastResults[id] = result;
      changed();
    }
    return result;
  }

  Future<void> _applyRecommendation(Room space, Room room) async {
    if (!_active) return;
    final pages = space.getState('net.deltiecord.space.pages')?.content;
    final announcements = pages?['announcement_channel_ids'];
    final value = announcements is List && announcements.contains(room.id)
        ? 'allMessages'
        : pages?['suggested_notifications'];
    // An explicit room preference always wins, including a pre-existing mute.
    final rules = client.globalPushRules;
    if ([
      ...?rules?.room,
      ...?rules?.override,
    ].any((rule) => rule.ruleId == room.id)) {
      return;
    }
    final state = switch (value) {
      'allMessages' => PushRuleState.notify,
      'mentionsOnly' => PushRuleState.mentionsOnly,
      'muted' => PushRuleState.dontNotify,
      _ => null,
    };
    if (state != null) await room.setPushRuleState(state);
  }

  Future<void> channelJoined(String spaceId, String roomId) async {
    if (!_active) return;
    final space = client.getRoomById(spaceId),
        room = client.getRoomById(roomId);
    if (space == null ||
        room == null ||
        space.membership != Membership.join ||
        room.membership != Membership.join) {
      return;
    }
    if (_excluded(spaceId).contains(roomId)) {
      await _set(
        spaceId,
        'excluded_channels',
        (_excluded(spaceId)..remove(roomId)).toList(),
      );
    }
    if (!_appliedRecommendations.contains(roomId)) {
      _pendingRecommendations[roomId] = spaceId;
      _recommendationAttempts[roomId] = DateTime.now();
      await _applyRecommendation(space, room);
      if (!_active) return;
      _appliedRecommendations.add(roomId);
      _pendingRecommendations.remove(roomId);
    }
    await _syncMuteRules();
  }

  Future<void> _joinRoom(
    String id, {
    Future<void> Function()? join,
    List<String>? via,
  }) async {
    final joined = Completer<void>();
    bool ready() {
      if (client.getRoomById(id)?.membership != Membership.join) return false;
      final status = client.onSyncStatus.value?.status;
      return status == null ||
          status == SyncStatus.finished ||
          status == SyncStatus.waitingForResponse;
    }

    final subscription = client.onSync.stream.listen((_) {
      if (!joined.isCompleted && ready()) joined.complete();
    });
    final processing = client.onSyncStatus.stream.listen((_) {
      if (!joined.isCompleted && ready()) joined.complete();
    });
    try {
      if (join == null) {
        await client
            .joinRoom(id, via: via)
            .timeout(const Duration(seconds: 20));
      } else {
        await join().timeout(const Duration(seconds: 20));
      }
      if (_active && !ready()) {
        await joined.future.timeout(const Duration(seconds: 20));
      }
    } finally {
      await subscription.cancel();
      await processing.cancel();
    }
  }

  Future<void> joinChannel(String roomId, {Future<void> Function()? join}) =>
      _joinRoom(roomId, join: join);

  Future<void> waitForJoinedRoom(String roomId) =>
      _joinRoom(roomId, join: () async {});

  Future<void> prepareToLeave(Set<String> roomIds) async {
    _departingSpaces.addAll(
      client.rooms
          .where((room) => room.isSpace && roomIds.contains(room.id))
          .map((room) => room.id),
    );
    for (final space
        in client.rooms
            .where((room) => room.isSpace && room.membership == Membership.join)
            .toList()) {
      if (!_active) return;
      if (_departingSpaces.contains(space.id)) continue;
      final excluded = _excluded(space.id);
      final leavingChildren = space.spaceChildren
          .map((child) => child.roomId)
          .whereType<String>()
          .where(roomIds.contains)
          .toSet();
      if (leavingChildren.isNotEmpty &&
          !excluded.containsAll(leavingChildren)) {
        await _set(
          space.id,
          'excluded_channels',
          {...excluded, ...leavingChildren}.toList(),
        );
      }
    }
    await Future.wait(
      _inFlight.values.toList().map(
        (request) => request.then<void>((_) {}, onError: (Object _) {}),
      ),
    );
  }

  void spaceJoined(String spaceId) {
    _departingSpaces.remove(spaceId);
    _signatures.remove(spaceId);
    _attempted.removeWhere((attempt) => attempt.startsWith('$spaceId|'));
    if (_active) _schedule();
  }

  String _ruleId(String space, String room) =>
      '$_mutePrefix${base64Url.encode(utf8.encode(jsonEncode([space, room]))).replaceAll('=', '')}';

  Future<void> _syncMuteRules() {
    _rulesAgain = true;
    return _ruleRequest ??= _runMuteRules().whenComplete(
      () => _ruleRequest = null,
    );
  }

  Future<void> _runMuteRules() async {
    if (!_active) return;
    if (_rulesRunning) {
      _rulesAgain = true;
      return;
    }
    _rulesRunning = true;
    try {
      do {
        _rulesAgain = false;
        final desired = <String, String>{
          for (final space in client.rooms)
            if (space.isSpace &&
                !_departingSpaces.contains(space.id) &&
                space.membership == Membership.join &&
                muted(space.id))
              for (final child in space.spaceChildren)
                if (child.roomId != null)
                  _ruleId(space.id, child.roomId!): child.roomId!,
        };
        final existing = {
          ..._installed,
          for (final rule in client.globalPushRules?.override ?? <PushRule>[])
            if (rule.ruleId.startsWith(_mutePrefix)) rule.ruleId,
        };
        for (final id in existing.difference(desired.keys.toSet())) {
          if (!_active) return;
          try {
            await client.deletePushRule(PushRuleKind.override, id);
          } on MatrixException catch (error) {
            if (error.errcode != 'M_NOT_FOUND') rethrow;
          }
          _installed.remove(id);
          _rulesChecked.remove(id);
        }
        for (final entry in desired.entries) {
          if (!_active) return;
          if (_rulesChecked.contains(entry.key)) continue;
          await client.setPushRule(
            PushRuleKind.override,
            entry.key,
            [],
            conditions: [
              PushCondition(
                kind: 'event_match',
                key: 'room_id',
                pattern: entry.value,
              ),
            ],
          );
          _installed.add(entry.key);
          _rulesChecked.add(entry.key);
        }
      } while (_active && _rulesAgain);
    } finally {
      _rulesRunning = false;
    }
  }

  void dispose() {
    _active = false;
    _timer?.cancel();
    unawaited(_sync?.cancel());
  }
}
