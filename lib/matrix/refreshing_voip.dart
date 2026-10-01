import 'dart:async';
import 'package:matrix/matrix.dart';

/// The SDK caches TURN credentials indefinitely. Keep their server-provided
/// lifetime instead; credentials never leave this boundary or enter diagnostics.
class TurnCredentialCache {
  TurnCredentialCache(this.fetch, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final Future<TurnServerCredentials> Function() fetch;
  final DateTime Function() now;
  TurnServerCredentials? _credentials;
  DateTime? _expires;
  Future<List<Map<String, dynamic>>>? _pending;

  Future<List<Map<String, dynamic>>> getServers() {
    if (_pending case final pending?) return pending;
    final credentials = _credentials;
    if (credentials != null && now().isBefore(_expires!)) {
      return Future.value(_servers(credentials));
    }
    return _pending = _refresh().whenComplete(() => _pending = null);
  }

  Future<List<Map<String, dynamic>>> _refresh() async {
    _credentials = null;
    final started = now();
    final credentials = await fetch().timeout(const Duration(seconds: 15));
    _expires = started.add(Duration(milliseconds: credentials.ttl * 900));
    _credentials = credentials;
    return _servers(credentials);
  }

  List<Map<String, dynamic>> _servers(TurnServerCredentials credentials) => [
    {
      'username': credentials.username,
      'credential': credentials.password,
      'urls': credentials.uris.map((uri) => uri.toString()).toList(),
    },
  ];
}

class RefreshingVoIP extends VoIP {
  RefreshingVoIP(super.client, super.delegate)
    : credentials = TurnCredentialCache(client.getTurnServer);

  final TurnCredentialCache credentials;
  Completer<void>? _joinReady;
  String? _joiningRoom;
  String? _joiningGroup;

  void beginJoining(GroupCallSession call) {
    finishJoining();
    _joiningRoom = call.room.id;
    _joiningGroup = call.groupCallId;
    _joinReady = Completer<void>();
  }

  void finishJoining() {
    _joinReady?.complete();
    _joinReady = null;
    _joiningRoom = null;
    _joiningGroup = null;
  }

  @override
  Future<void> onCallInvite(
    Room room,
    String remoteUserId,
    String? remoteDeviceId,
    Map<String, dynamic> content,
  ) async {
    // Group.enter publishes membership before installing Mesh listeners.
    // Hold only that group's invites until the local stream/listeners exist.
    final ready = _joinReady;
    if (ready != null &&
        room.id == _joiningRoom &&
        content['conf_id'] == _joiningGroup) {
      try {
        await ready.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        return;
      }
      if (currentGroupCID == null) return;
    }
    await super.onCallInvite(room, remoteUserId, remoteDeviceId, content);
  }

  @override
  Future<List<Map<String, dynamic>>> getIceServers() async {
    try {
      return await credentials.getServers();
    } catch (_) {
      // Local/direct connectivity can still work without TURN. Never return
      // expired relay credentials, nor include their values in an error.
      return [];
    }
  }
}
