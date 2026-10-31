import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';

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
