import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'browser_lifecycle.dart';
import 'browser_private_store.dart';

/// Optional, device-local read-only snapshots. Never exports account identity,
/// Olm ratchets, recovery secrets or a whole SDK database to the push worker.
/// Only recent inbound Megolm sessions for currently joined rooms are retained.
abstract final class BrowserPushPreviews {
  static final enabled = ValueNotifier(false);
  static Client? _client;
  static StreamSubscription<dynamic>? _sync;
  static final _rooms = <String, StreamSubscription<String>>{};
  static final _sessions = <String, Map<String, Object?>>{};
  static Timer? _timer;
  static var _generation = 0;
  static var _allowed = false;
  static Future<void> _writes = Future.value();

  static Future<void> start(Client client) async {
    if (!kIsWeb) return;
    stop();
    _client = client;
    final optIn = await BrowserPrivateStore.read('push-preview-opt-in');
    if (!identical(client, _client)) return;
    enabled.value = optIn == 'true';
    _sync = client.onSync.stream.listen((_) => refresh());
    refresh();
  }

  static void setAllowed(bool value) {
    if (!kIsWeb || value == _allowed) return;
    _allowed = value;
    if (!value) {
      _generation++;
      _timer?.cancel();
      _sessions.clear();
      unawaited(_write(null));
    } else {
      refresh();
    }
  }

  static Future<void> setEnabled(bool value) async {
    if (!kIsWeb) return;
    enabled.value = value;
    _generation++;
    _timer?.cancel();
    _sessions.clear();
    // Clear first, so disabling remains safe even if preference persistence fails.
    await _write(null);
    await BrowserPrivateStore.write('push-preview-opt-in', '$value');
    if (value) refresh();
  }

  static void refresh() {
    final client = _client;
    if (!kIsWeb ||
        client == null ||
        !enabled.value ||
        !_allowed ||
        !client.isLogged()) {
      return;
    }
    final joined = client.rooms
        .where((r) => r.membership == Membership.join)
        .toList();
    final ids = joined.map((r) => r.id).toSet();
    for (final id in _rooms.keys.toList()) {
      if (!ids.contains(id)) unawaited(_rooms.remove(id)!.cancel());
    }
    _sessions.removeWhere((_, s) => !ids.contains(s['room']));
    for (final room in joined) {
      _rooms.putIfAbsent(
        room.id,
        () => room.onSessionKeyReceived.stream.listen((id) {
          unawaited(
            _capture(room.id, id, _generation).then((_) => _schedule()),
          );
        }),
      );
    }
    _schedule();
  }

  static void _schedule() {
    if (_timer?.isActive == true || !enabled.value || !_allowed) return;
    _timer = Timer(const Duration(seconds: 2), () => unawaited(_snapshot()));
  }

  static Future<void> _capture(String room, String id, int generation) async {
    final client = _client;
    if (client == null ||
        !enabled.value ||
        !_allowed ||
        _sessions.containsKey(id)) {
      return;
    }
    try {
      final key = await client.encryption?.keyManager.loadInboundGroupSession(
        room,
        id,
      );
      if (generation != _generation || key?.inboundGroupSession == null) return;
      final device = client.getUserDeviceKeysByCurve25519Key(key!.senderKey);
      // Do not display an unbound sender identity on the lock screen.
      if (device == null ||
          device.ed25519Key != key.senderClaimedKeys['ed25519'] ||
          key.forwardingCurve25519KeyChain.isNotEmpty) {
        return;
      }
      _sessions[id] = {
        'room': room,
        'id': id,
        'senderKey': key.senderKey,
        'sender': device.userId,
        'name': client
            .getRoomById(room)
            ?.unsafeGetUserFromMemoryOrFallback(device.userId)
            .displayName,
        'key': key.inboundGroupSession!.exportAtFirstKnownIndex(),
      };
      while (_sessions.length > 256) {
        _sessions.remove(_sessions.keys.first);
      }
    } catch (_) {
      // Missing/unknown keys simply retain generic notifications.
    }
  }

  static Future<void> _snapshot() async {
    final client = _client;
    final generation = _generation;
    if (client == null || !client.isLogged() || !enabled.value || !_allowed) {
      return;
    }
    final rooms = client.rooms
        .where((r) => r.membership == Membership.join)
        .toList();
    // Warm only recent keys, never enumerate/decrypt a large history database.
    for (final room in rooms.take(256)) {
      final event = room.lastEvent;
      final content = event?.originalSource?.content ?? event?.content;
      final id = content?['session_id'];
      if (id is String) await _capture(room.id, id, generation);
      if (generation != _generation) return;
    }
    final token = client.accessToken;
    final server = client.homeserver;
    if (token == null || server?.scheme != 'https') return;
    final json = jsonEncode({
      'owner': '${client.userID}|${client.deviceID}',
      'user': client.userID,
      'homeserver': server.toString(),
      'token': token,
      'expires': DateTime.now()
          .add(const Duration(days: 7))
          .millisecondsSinceEpoch,
      'rooms': rooms.map((r) => r.id).toList(),
      'sessions': _sessions.values.toList(),
    });
    if (generation == _generation) await _write(json);
  }

  static Future<void> _write(String? json) {
    final next = _writes.then((_) => writeBrowserPushPreview(json));
    _writes = next.catchError((Object _) {});
    return _writes;
  }

  static void stop() {
    _generation++;
    _timer?.cancel();
    unawaited(_sync?.cancel());
    _sync = null;
    for (final subscription in _rooms.values) {
      unawaited(subscription.cancel());
    }
    _rooms.clear();
    _sessions.clear();
    _client = null;
  }

  static Future<void> clear() async {
    if (!kIsWeb) return;
    stop();
    enabled.value = false;
    await _write(null);
    await BrowserPrivateStore.write('push-preview-opt-in', null);
  }
}
