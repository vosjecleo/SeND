import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:deltiecord/matrix/rtc/rtc_sfu_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_transport_api.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'rtc_probe_cleanup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nonce = Uri.base.queryParameters['nonce'];
  if (nonce == null || Uri.base.host != '127.0.0.1') return;
  Uri endpoint(String name) =>
      Uri.base.replace(path: '/probe/$name', queryParameters: {'nonce': nonce});
  RtcMatrixClient? client;
  RtcSfuSession? session;
  String? roomId;
  var stage = 'initialization';
  Future<void> report(Map<String, Object> data) async {
    await http.post(endpoint('result'), body: jsonEncode(data));
  }

  try {
    final fixture =
        jsonDecode((await http.get(endpoint('fixture'))).body) as Map;
    await vodozemac.init();
    final database = await MatrixSdkDatabase.init('rtc-browser-temporary');
    client =
        RtcMatrixClient(
            'SeND RTC temporary browser test',
            database: database,
            logLevel: Level.error,
            importantStateEvents: {rtcCallMemberType},
            shareKeysWith: ShareKeysWith.all,
          )
          ..homeserver = Uri.parse('https://matrix.deltie.net')
          ..syncPresence = PresenceType.offline;
    stage = 'login';
    while (true) {
      try {
        await client.login(
          LoginType.mLoginPassword,
          identifier: AuthenticationUserIdentifier(
            user: fixture['user'] as String,
          ),
          password: fixture['password'] as String,
          initialDeviceDisplayName: 'SeND RTC temporary browser test',
        );
        break;
      } on MatrixException catch (error) {
        if (error.errcode != 'M_LIMIT_EXCEEDED') rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: (error.retryAfterMs ?? 60000) + 1000),
        );
      }
    }
    await client.firstSyncReceived;
    await removeAbandonedRtcProbeDevices(client, fixture['password'] as String);
    stage = 'room join';
    roomId = fixture['room'] as String;
    await client.joinRoom(roomId);
    await client.waitForRoomInSync(roomId, join: true);
    final api = RtcTransportApi(client);
    final focus = (await api.discover()).first;
    session = RtcSfuSession(
      matrixRoom: client.getRoomById(roomId)!,
      transport: focus,
      api: api,
      preferences: const AppPreferences(outputVolume: 0, callSound: false),
      deafened: true,
      onProgress: (value) {
        stage = value;
      },
    );
    await report({'stage': 'joining'});
    await session.start();
    stage = 'media';
    while (true) {
      await report({
        'stage': stage,
        'members': session.members.length,
        'crypto': session.cryptoDiagnostics,
      });
      final command =
          jsonDecode((await http.get(endpoint('stop'))).body) as Map;
      if (command['stop'] == true) {
        break;
      }
      if (command['camera'] == true && !session.cameraEnabled) {
        await session.setCameraEnabled(true);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  } catch (error) {
    await report({
      'stage': stage,
      'error': error is MatrixException
          ? error.errcode
          : error.runtimeType.toString(),
    });
  } finally {
    await session?.close();
    if (client != null) {
      if (roomId != null) {
        try {
          await client.leaveRoom(roomId);
        } catch (_) {}
      }
      try {
        await client.abortSync();
        await client.request(RequestType.POST, '/client/v3/logout', data: {});
      } catch (_) {}
      await client.dispose();
    }
    await http.post(endpoint('finished'));
  }
}
