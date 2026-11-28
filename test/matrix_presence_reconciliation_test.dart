import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'support/backend_browser_fixture_stub.dart'
    if (dart.library.js_interop) 'support/backend_browser_fixture_web.dart';

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

class _OwnClient extends _Client {
  bool failWrites = true;
  Completer<void>? writeGate;
  final writtenStatuses = <String?>[];
  @override
  String get userID => '@self:example.org';
  @override
  Future<void> setPresence(
    String userId,
    PresenceType presence, {
    String? statusMsg,
  }) async {
    if (failWrites) throw StateError('Presence publication unavailable');
    writtenStatuses.add(statusMsg);
    await writeGate?.future;
  }
}

class _LoggedClient extends _Client {
  @override
  bool isLogged() => true;
}

class _MobileBackend extends MatrixBackend {
  _MobileBackend({required super.client});
  @override
  bool get supportsActivityDetection => false;
}

class _DirectRoom extends Room {
  _DirectRoom(Client client) : super(id: '!dm:example.org', client: client) {
    setState(
      Event.fromJson({
        'event_id': r'$member',
        'type': 'm.room.member',
        'state_key': '@peer:example.org',
        'sender': '@peer:example.org',
        'origin_server_ts': 1,
        'content': {'membership': 'join', 'displayname': 'Peer'},
      }, this),
    );
  }
  @override
  bool get isDirectChat => true;
  @override
  String get directChatMatrixID => '@peer:example.org';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => addTearDown(installBackendBrowserFixture()));
  const peer = '@peer:example.org';
  test(
    'a presence burst updates state immediately and sends one UI notification',
    () async {
      final client = _Client();
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      var updates = 0;
      backend.addListener(() => updates++);
      for (var index = 0; index < 20; index++) {
        final id = '@peer$index:example.org';
        final value = CachedPresence(PresenceType.online, 0, null, true, id);
        // ignore: deprecated_member_use
        client.presences[id] = value;
        client.onPresenceChanged.add(value);
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(updates, 1);
      expect(client.presenceReads, 0);
    },
  );
  test(
    'a newly visible DM refreshes Offline before any typing or message',
    () async {
      final client = _LoggedClient();
      client.rooms = [_DirectRoom(client)];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.getUserProfile(peer);
      await Future<void>.delayed(Duration.zero);
      final reads = client.presenceReads;
      client.serverState = PresenceType.online;
      await backend.refreshVisibleAvatar('!dm:example.org');
      await Future<void>.delayed(Duration.zero);
      expect(client.presenceReads, reads + 1);
      expect(backend.rooms.single.presence, UserPresence.online);
    },
  );
  test(
    'SDK presence alone immediately updates DM and cached profile before full sync',
    () async {
      final client = _Client();
      client.rooms = [_DirectRoom(client)];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.getUserProfile(peer);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(backend.rooms.single.presence, UserPresence.offline);
      final reads = client.presenceReads;
      var updates = 0;
      backend.addListener(() => updates++);
      final value = CachedPresence(PresenceType.online, 0, null, true, peer);
      // The SDK's documented ordering: cache write, presence stream, then later
      // account/device processing and the final onSync event (not emitted here).
      // ignore: deprecated_member_use
      client.presences[peer] = value;
      client.onPresenceChanged.add(value);
      // Both native presence bursts and the web backend publish within one
      // frame; they do not wait for a completed sync or a network request.
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(updates, greaterThan(0));
      expect(backend.rooms.single.presence, UserPresence.online);
      expect(
        (await backend.getUserProfile(peer)).presence,
        UserPresence.online,
      );
      expect(client.presenceReads, reads);
    },
  );
  test(
    'own island reads SDK presence without waiting for profile hydration',
    () async {
      final client = _OwnClient();
      final backend = _MobileBackend(client: client);
      addTearDown(backend.dispose);
      final value = CachedPresence(
        PresenceType.online,
        0,
        null,
        true,
        client.userID,
      );
      // ignore: deprecated_member_use
      client.presences[client.userID] = value;
      client.onPresenceChanged.add(value);
      await Future<void>.delayed(Duration.zero);
      expect(backend.profilePresence, UserPresence.online);
      expect(client.profileReads, 0);
      expect(client.presenceReads, 0);
    },
  );
  test(
    'disposed backend ignores later presence events from the previous client',
    () async {
      final client = _Client();
      final backend = MatrixBackend(client: client);
      var updates = 0;
      backend.addListener(() => updates++);
      backend.dispose();
      final before = updates;
      final value = CachedPresence(PresenceType.online, 0, null, true, peer);
      client.onPresenceChanged.add(value);
      await Future<void>.delayed(Duration.zero);
      expect(updates, before);
    },
  );
  test(
    'a successful own publication updates Online without waiting for its sync echo',
    () async {
      addTearDown(installBackendBrowserFixture(publicationSucceeded: true));
      final client = _OwnClient()
        ..failWrites = false
        ..gate = Completer<GetPresenceResponse>();
      final backend = _MobileBackend(client: client);
      addTearDown(backend.dispose);
      // The native test host is Linux; model a foreground, non-idle phone.
      backend.setDesktopIdle(false);
      await backend.refreshProfile();
      await Future<void>.delayed(Duration.zero);
      expect(backend.profilePresence, UserPresence.online);
      client.gate!.complete(
        GetPresenceResponse(presence: PresenceType.offline),
      );
      await Future<void>.delayed(Duration.zero);
      expect(backend.profilePresence, UserPresence.online);
    },
  );
  test(
    'own custom status survives a presence-only reply and profile refresh',
    () async {
      final client = _OwnClient()
        ..failWrites = false
        ..serverState = PresenceType.online;
      final backend = _MobileBackend(client: client);
      addTearDown(backend.dispose);
      final id = client.userID;
      await backend.refreshProfile();
      await backend.updateOwnProfileFields(statusMessage: 'Making tea');
      await backend.getUserProfile(id, refresh: true);
      await Future<void>.delayed(Duration.zero);
      expect(backend.profileStatusMessage, 'Making tea');
      expect((await backend.getUserProfile(id)).statusMessage, 'Making tea');

      final offline = CachedPresence(PresenceType.offline, 0, null, false, id);
      // ignore: deprecated_member_use
      client.presences[id] = offline;
      client.onPresenceChanged.add(offline);
      await Future<void>.delayed(Duration.zero);
      expect(backend.profileStatusMessage, 'Making tea');

      await backend.updateOwnProfileFields(statusMessage: '');
      expect(backend.profileStatusMessage, isNull);
      expect((await backend.getUserProfile(id)).statusMessage, isNull);
    },
  );
  test('an explicit status edit waits for an older presence write', () async {
    final gate = Completer<void>();
    final client = _OwnClient()
      ..failWrites = false
      ..writeGate = gate;
    final backend = _MobileBackend(client: client);
    addTearDown(backend.dispose);
    await backend.refreshProfile();
    await Future<void>.delayed(Duration.zero);
    expect(client.writtenStatuses, [null]);

    final edit = backend.updateOwnProfileFields(statusMessage: 'New status');
    await Future<void>.delayed(Duration.zero);
    expect(client.writtenStatuses, [null]);
    gate.complete();
    await edit;

    expect(client.writtenStatuses, [null, 'New status']);
    expect(backend.profileStatusMessage, 'New status');
  });
  test(
    'async own presence updates the island without a second profile refresh',
    () async {
      final client = _OwnClient()..gate = Completer<GetPresenceResponse>();
      final backend = _MobileBackend(client: client);
      addTearDown(backend.dispose);
      await backend.refreshProfile();
      expect(backend.profilePresence, UserPresence.offline);
      client.gate!.complete(GetPresenceResponse(presence: PresenceType.online));
      await Future<void>.delayed(Duration.zero);
      expect(backend.profilePresence, UserPresence.online);
    },
  );
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
