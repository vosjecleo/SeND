import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('presence-regression', database: _Database()) {
    homeserver = Uri.parse('https://matrix.example.org');
  }
  int presenceReads = 0, profileReads = 0;
  PresenceType serverState = PresenceType.offline;
  Completer<GetPresenceResponse>? gate;
  @override
  Future<GetPresenceResponse> getPresence(String userId) async {
    presenceReads++;
    return gate?.future ??
        GetPresenceResponse(presence: serverState, currentlyActive: false);
  }

  @override
  Future<CachedProfileInformation> getUserProfile(
    String userId, {
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async {
    profileReads++;
    return CachedProfileInformation.fromProfile(
      ProfileInformation(displayname: 'Peer'),
      outdated: false,
      updated: DateTime.now(),
    );
  }

  @override
  Future<Capabilities> getCapabilities() async =>
      throw StateError('No custom fields');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const peer = '@peer:example.org';
  test(
    'a cached Online contact is reconciled with server Offline, and vice versa',
    () async {
      final client = _Client();
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      // ignore: deprecated_member_use
      client.presences[peer] = CachedPresence(
        PresenceType.online,
        const Duration(days: 2).inMilliseconds,
        'Old status',
        false,
        peer,
      );
      await backend.getUserProfile(peer, refresh: true);
      await Future<void>.delayed(Duration.zero);
      final repaired = await backend.getUserProfile(peer);
      expect(repaired.presence, UserPresence.offline);
      expect(repaired.statusMessage, isNull);
      expect(client.presenceReads, 1);
      client.serverState = PresenceType.online;
      await backend.getUserProfile(peer, refresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await backend.getUserProfile(peer)).presence,
        UserPresence.online,
      );
      expect(client.presenceReads, 2);
    },
  );
  test(
    'profile text loads without waiting for a slow presence endpoint',
    () async {
      final client = _Client()..gate = Completer<GetPresenceResponse>();
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final profile = await backend
          .getUserProfile(peer)
          .timeout(const Duration(seconds: 1));
      expect(profile.displayName, 'Peer');
      expect(client.gate!.isCompleted, isFalse);
      expect(client.presenceReads, 1);
      client.gate!.complete(GetPresenceResponse(presence: PresenceType.online));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await backend.getUserProfile(peer)).presence,
        UserPresence.online,
      );
      expect(client.profileReads, 1);
    },
  );
  test(
    'a newer SDK sync entry cannot be overwritten by a late REST response',
    () async {
      final client = _Client()..gate = Completer<GetPresenceResponse>();
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.getUserProfile(peer);
      // Simulate SDK sync updating its shared map before the backend callback.
      // ignore: deprecated_member_use
      client.presences[peer] = CachedPresence(
        PresenceType.offline,
        0,
        null,
        false,
        peer,
      );
      client.gate!.complete(GetPresenceResponse(presence: PresenceType.online));
      await Future<void>.delayed(Duration.zero);
      expect(
        (await backend.getUserProfile(peer)).presence,
        UserPresence.offline,
      );
    },
  );
  test(
    'late presence after disposal cannot restore the old session cache',
    () async {
      final client = _Client()..gate = Completer<GetPresenceResponse>();
      final backend = MatrixBackend(client: client);
      await backend.getUserProfile(peer);
      backend.dispose();
      client.gate!.complete(GetPresenceResponse(presence: PresenceType.online));
      await Future<void>.delayed(Duration.zero);
      // ignore: deprecated_member_use
      expect(client.presences[peer], isNull);
    },
  );
}
