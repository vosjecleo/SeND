import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:deltiecord/matrix/rtc/rtc_transport_api.dart';

class WireClient extends RtcMatrixClient {
  WireClient(DatabaseApi database, http.Client httpClient)
    : super('rtc-test', database: database, httpClient: httpClient) {
    homeserver = Uri.parse('https://matrix.example.org');
  }
  @override
  String? get bearerToken => 'public-session-fixture';
  @override
  String? get userID => '@me:example.org';
  @override
  String? get deviceID => 'TEST';
  @override
  Future<DiscoveryInformation> getWellknown({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async => DiscoveryInformation.fromJson({
    'm.homeserver': {'base_url': 'https://matrix.example.org'},
    'org.matrix.msc4143.rtc_foci': [
      {'type': 'livekit', 'livekit_service_url': 'https://rtc.example.org/jwt'},
    ],
  });
}

Future<WireClient> wireClient(
  Future<http.Response> Function(http.Request) respond,
) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  final database = await MatrixSdkDatabase.init(
    'rtc-test',
    database: db,
    sqfliteFactory: databaseFactoryFfi,
  );
  return WireClient(database, MockClient(respond));
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'transport endpoint fallback is limited to unsupported endpoints',
    () async {
      final paths = <String>[];
      final client = await wireClient((request) async {
        paths.add(request.url.path);
        expect(
          request.headers['authorization'],
          'Bearer public-session-fixture',
        );
        return jsonResponse({'errcode': 'M_UNRECOGNIZED'}, 404);
      });
      addTearDown(client.dispose);
      final transports = await RtcTransportApi(client).discover();
      expect(paths, [
        '/_matrix/client/v1/rtc/transports',
        '/_matrix/client/unstable/org.matrix.msc4143/rtc/transports',
      ]);
      expect(
        transports.single.serviceUrl.toString(),
        'https://rtc.example.org/jwt',
      );
    },
  );

  test(
    'denied transport discovery never falls back to a public service',
    () async {
      var requests = 0;
      final client = await wireClient((_) async {
        requests++;
        return jsonResponse({'errcode': 'M_FORBIDDEN'}, 403);
      });
      addTearDown(client.dispose);
      await expectLater(
        RtcTransportApi(client).discover(),
        throwsA(isA<MatrixException>()),
      );
      expect(requests, 1);
    },
  );

  test(
    'standalone authorization sends OpenID only, without redirect following',
    () async {
      final client = await wireClient((request) async {
        if (request.url.host == 'matrix.example.org') {
          expect(request.url.path, contains('/openid/request_token'));
          expect(
            request.headers['authorization'],
            'Bearer public-session-fixture',
          );
          return jsonResponse({
            'access_token': 'public-openid-fixture',
            'matrix_server_name': 'example.org',
            'expires_in': 60,
            'token_type': 'Bearer',
          });
        }
        expect(request.url.toString(), 'https://rtc.example.org/jwt/sfu/get');
        expect(request.followRedirects, isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        final body = jsonDecode(request.body) as Map;
        expect(body['room'], '!room:example.org');
        expect(body['device_id'], 'TEST');
        expect(body['openid_token']['access_token'], 'public-openid-fixture');
        expect(request.body, isNot(contains('public-session-fixture')));
        return jsonResponse({
          'url': 'wss://sfu.example.org',
          'jwt': 'public-jwt-fixture',
        });
      });
      addTearDown(client.dispose);
      final result = await RtcTransportApi(client).authorize(
        transport: RtcTransport(
          serviceUrl: Uri.parse('https://rtc.example.org/jwt/'),
        ),
        roomId: '!room:example.org',
        memberId: '@me:example.org:TEST',
      );
      expect(result.url.scheme, 'wss');
      expect(result.toString(), isNot(contains(result.jwt)));
    },
  );

  test('modern SFU authorization is mediated by our homeserver', () async {
    final client = await wireClient((request) async {
      expect(request.url.host, 'matrix.example.org');
      expect(
        request.url.path,
        '/_matrix/client/unstable/io.element.msc4195/rtc/livekit/get_token',
      );
      final body = jsonDecode(request.body) as Map;
      expect(body, {
        'url': 'wss://remote.example.org',
        'room_id': '!room:example.org',
        'slot_id': rtcRoomSlot,
        'member_id': 'member',
        'server_name': 'remote.example.org:8448',
      });
      return jsonResponse({'jwt': 'public-jwt-fixture'});
    });
    addTearDown(client.dispose);
    final result = await RtcTransportApi(client).authorize(
      transport: RtcTransport(url: Uri.parse('wss://remote.example.org')),
      roomId: '!room:example.org',
      memberId: 'member',
      publishingUserId: '@friend:remote.example.org:8448',
    );
    expect(result.url.host, 'remote.example.org');
  });

  test(
    'authorization errors do not expose service response bodies or tokens',
    () async {
      final client = await wireClient(
        (request) async => request.url.host == 'matrix.example.org'
            ? jsonResponse({
                'access_token': 'public-openid-fixture',
                'matrix_server_name': 'example.org',
                'expires_in': 60,
                'token_type': 'Bearer',
              })
            : jsonResponse({'error': 'public-jwt-fixture'}, 403),
      );
      addTearDown(client.dispose);
      try {
        await RtcTransportApi(client).authorize(
          transport: RtcTransport(
            serviceUrl: Uri.parse('https://rtc.example.org'),
          ),
          roomId: '!room:example.org',
          memberId: 'member',
        );
        fail('Authorization must fail');
      } catch (error) {
        expect(error.toString(), contains('403'));
        expect(error.toString(), isNot(contains('public-jwt-fixture')));
        expect(error.toString(), isNot(contains('public-openid-fixture')));
      }
    },
  );
}
