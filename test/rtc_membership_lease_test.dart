import 'dart:convert';
import 'dart:async';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_membership_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Client extends RtcMatrixClient {
  _Client(
    super.clientName, {
    required super.database,
    required super.httpClient,
  });
  @override
  String? get bearerToken => 'public-session-fixture';
  @override
  String? get userID => '@me:example.org';
  @override
  String? get deviceID => 'DEVICE';
  @override
  bool get encryptionEnabled => true;
  @override
  late final Encryption encryption = Encryption(client: this);
  Future<List<RtcMember>>? hydrationGate;
  @override
  Future<List<RtcMember>> hydrateRtcMembers(Room room) =>
      hydrationGate ?? super.hydrateRtcMembers(room);
}

class _AllowedDevice extends Fake implements DeviceKeys {
  bool allowed = true;
  @override
  bool get encryptToDevice => allowed;
}

class _ResendClient extends _Client {
  _ResendClient(
    super.clientName, {
    required super.database,
    required super.httpClient,
  });
  final sentKeys = <Map<String, dynamic>>[];
  @override
  Future<void> updateUserDeviceKeys({Set<String>? additionalUsers}) async {}
  @override
  Future<void> sendToDeviceEncrypted(
    List<DeviceKeys> devices,
    String type,
    Map<String, dynamic> message, {
    String? messageId,
    bool onlyVerified = false,
  }) async {
    expect(devices, hasLength(1));
    expect(devices.single.encryptToDevice, true);
    sentKeys.add(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost call key recovers without a membership change and never bypasses trust',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final database = await MatrixSdkDatabase.init(
        'rtc-resend',
        database: db,
        sqfliteFactory: databaseFactoryFfi,
      );
      final client = _ResendClient(
        'rtc-resend',
        database: database,
        httpClient: MockClient(
          (request) async =>
              http.Response('{"event_id":"event","delay_id":"leave"}', 200),
        ),
      )..homeserver = Uri.parse('https://matrix.example.org');
      addTearDown(client.dispose);
      final room = Room(
        id: '!call:example.org',
        client: client,
        membership: Membership.join,
      );
      final allowed = _AllowedDevice();
      client.userDeviceKeys['@peer:example.org'] = DeviceKeysList(
        '@peer:example.org',
        client,
      )..deviceKeys['PEER'] = allowed;
      final member = RtcMember(
        userId: '@peer:example.org',
        deviceId: 'PEER',
        memberId: 'peer-member',
        createdAt: DateTime(2026),
        expiresAt: DateTime(2030),
        transports: const [],
      );
      client.hydrationGate = Future.value([member]);
      var now = DateTime.utc(2026, 11, 5);
      final errors = <Object>[];
      final session = RtcMembershipSession(
        room: room,
        transport: RtcTransport(
          serviceUrl: Uri.parse('https://rtc.example.org'),
        ),
        clock: () => now,
        heartbeatTick: const Duration(days: 1),
        installKey: (_, _, _) async {},
        onMembersChanged: (_) {},
        onError: errors.add,
        pauseMedia: (_) async {},
      );
      addTearDown(session.close);
      await session.start();
      final first = client.sentKeys.single['media_key'];
      now = now.add(const Duration(seconds: 21));
      await session.refresh();
      expect(client.sentKeys, hasLength(2));
      expect(client.sentKeys.last['media_key'], first);
      allowed.allowed = false;
      now = now.add(const Duration(seconds: 21));
      await session.refresh();
      expect(client.sentKeys, hasLength(2));
      expect(session.hasUnverifiedDevices, true);
      expect(errors, isEmpty);
    },
  );
  for (final cancelsOnStateWrite in [false, true]) {
    test(
      'lease renewal preserves epoch (server cancels old jobs: $cancelsOnStateWrite)',
      () async {
        sqfliteFfiInit();
        final db = await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(singleInstance: false),
        );
        final database = await MatrixSdkDatabase.init(
          'rtc-lease',
          database: db,
          sqfliteFactory: databaseFactoryFfi,
        );
        final writes = <Map>[];
        final heartbeatIds = <String>[];
        final errors = <Object>[];
        var leaveId = 0;
        String? activeReservation;
        final client = _Client(
          'rtc-lease',
          database: database,
          httpClient: MockClient((request) async {
            if (request.method == 'PUT' &&
                request.url.queryParameters.isEmpty) {
              if (cancelsOnStateWrite) activeReservation = null;
              writes.add(jsonDecode(request.body) as Map);
              return http.Response('{"event_id":"public-event"}', 200);
            }
            if (request.method == 'PUT') {
              activeReservation = 'leave-${++leaveId}';
              return http.Response(
                jsonEncode({'delay_id': activeReservation}),
                200,
              );
            }
            final id = request.url.path.split('/').last;
            heartbeatIds.add(id);
            if (id != activeReservation) {
              return http.Response('{"errcode":"M_NOT_FOUND"}', 404);
            }
            return http.Response('{}', 200);
          }),
        )..homeserver = Uri.parse('https://matrix.example.org');
        addTearDown(client.dispose);
        var now = DateTime.utc(2026, 10, 13);
        final session = RtcMembershipSession(
          room: Room(id: '!call:example.org', client: client),
          transport: RtcTransport(
            serviceUrl: Uri.parse('https://rtc.example.org'),
          ),
          clock: () => now,
          installKey: (_, key, index) async {
            expect(key.length, 32);
          },
          onMembersChanged: (_) {},
          onError: errors.add,
          pauseMedia: (_) async {},
        );
        addTearDown(session.close);
        await session.start();
        final epoch = writes.single['created_ts'];
        for (var i = 0; i < 30; i++) {
          now = now.add(const Duration(seconds: 5));
          await session.refresh();
          final last = writes.last;
          expect(last['created_ts'], epoch);
          expect(
            DateTime.fromMillisecondsSinceEpoch(last['created_ts'] as int)
                .add(Duration(milliseconds: last['expires'] as int))
                .difference(now),
            greaterThanOrEqualTo(const Duration(seconds: 80)),
          );
        }
        expect(writes.length, greaterThanOrEqualTo(4));
        if (cancelsOnStateWrite) {
          expect(leaveId, greaterThanOrEqualTo(3));
        } else {
          expect(leaveId, 1);
          expect(heartbeatIds.toSet(), {'leave-1'});
        }
        expect(errors, isEmpty);
        if (cancelsOnStateWrite) {
          // Graceful shutdown must still clear membership if the server
          // cancelled the reservation just before the client leaves.
          activeReservation = null;
          await session.close();
          expect(writes.last, isEmpty);
        }
      },
    );
  }
  test('slow membership decryption cannot block lease heartbeats', () async {
    var heartbeats = 0, writes = 0, reservations = 0;
    final client = await (() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final database = await MatrixSdkDatabase.init(
        'rtc-slow-lease',
        database: db,
        sqfliteFactory: databaseFactoryFfi,
      );
      return _Client(
        'rtc-slow-lease',
        database: database,
        httpClient: MockClient((request) async {
          if (request.method == 'PUT') {
            if (request.url.queryParameters.isEmpty) {
              writes++;
              return http.Response('{"event_id":"public-event"}', 200);
            }
            return http.Response('{"delay_id":"leave-${++reservations}"}', 200);
          }
          heartbeats++;
          return http.Response('{}', 200);
        }),
      )..homeserver = Uri.parse('https://matrix.example.org');
    })();
    final gate = Completer<List<RtcMember>>();
    client.hydrationGate = gate.future;
    var now = DateTime.utc(2026, 10, 13);
    final errors = <Object>[];
    final session = RtcMembershipSession(
      room: Room(id: '!call:example.org', client: client),
      transport: RtcTransport(serviceUrl: Uri.parse('https://rtc.example.org')),
      clock: () => now,
      heartbeatTick: const Duration(milliseconds: 10),
      installKey: (_, _, _) async {},
      onMembersChanged: (_) {},
      onError: errors.add,
      pauseMedia: (_) async {},
    );
    final starting = session.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    for (var i = 0; i < 12; i++) {
      now = now.add(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    gate.complete([]);
    await starting;
    await session.close();
    await client.dispose();
    expect(heartbeats, greaterThanOrEqualTo(10));
    expect(writes, 2);
    expect(reservations, 1);
    expect(errors, isEmpty);
  });
}
