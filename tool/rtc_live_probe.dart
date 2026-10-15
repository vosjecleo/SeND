import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show RTCVideoRenderer;
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:deltiecord/matrix/rtc/rtc_sfu_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_transport_api.dart';
import 'rtc_browser_probe.dart';
import 'rtc_probe_cleanup.dart';

/// Explicit operator-run live test. Credentials are read only from the local
/// mode-0600 file, never command arguments, build defines or test output.
/// Creates one private room and fresh devices; cleanup leaves and logs out.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final clients = <RtcMatrixClient>[];
  final sessions = <RtcSfuSession>[];
  final renderers = <RTCVideoRenderer>[];
  final browser = Platform.environment['RTC_BROWSER_TEST'] == '1'
      ? RtcBrowserProbe()
      : null;
  final participantCount = browser != null
      ? 3
      : (int.tryParse(Platform.environment['RTC_NATIVE_PARTICIPANTS'] ?? '') ??
                3)
            .clamp(2, 3);
  String? roomId;
  var success = false;
  var stage = 'initialization';
  try {
    final file = File('/home/cleo/Creds/creds.txt');
    if ((file.statSync().mode & 63) != 0) {
      throw StateError('Credentials must be mode 0600');
    }
    final accounts = (await file.readAsLines())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.split(','))
        .toList();
    if (accounts.length < 3 ||
        accounts.any(
          (row) =>
              row.length < 2 ||
              !row[0].startsWith('@') ||
              !row[0].endsWith(':deltie.net'),
        )) {
      throw StateError('Invalid test-account file');
    }
    await vodozemac.init();
    sqfliteFfiInit();
    for (var i = 0; i < (browser == null ? participantCount : 2); i++) {
      stage = 'account ${i + 1} login';
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      final database = await MatrixSdkDatabase.init(
        'send-rtc-test-$i',
        database: db,
        sqfliteFactory: databaseFactoryFfi,
      );
      final client =
          RtcMatrixClient(
              'SeND RTC temporary test',
              database: database,
              logLevel: Level.error,
              shareKeysWith: ShareKeysWith.all,
              importantStateEvents: {rtcCallMemberType},
            )
            ..homeserver = Uri.parse('https://matrix.deltie.net')
            ..syncPresence = PresenceType.offline;
      clients.add(client);
      while (true) {
        try {
          await client
              .login(
                LoginType.mLoginPassword,
                identifier: AuthenticationUserIdentifier(user: accounts[i][0]),
                password: accounts[i][1],
                initialDeviceDisplayName: 'SeND RTC temporary test',
              )
              .timeout(const Duration(seconds: 30));
          break;
        } on MatrixException catch (error) {
          if (error.errcode != 'M_LIMIT_EXCEEDED') rethrow;
          final delay = error.retryAfterMs ?? 60000;
          if (delay > 600000) rethrow;
          debugPrint('RTC_LIVE: login rate limited, waiting ${delay ~/ 1000}s');
          await Future<void>.delayed(Duration(milliseconds: delay + 1000));
        }
      }
      await client.firstSyncReceived?.timeout(const Duration(seconds: 30));
      final removed = await removeAbandonedRtcProbeDevices(
        client,
        accounts[i][1],
      );
      debugPrint('RTC_LIVE: removed $removed abandoned test devices');
      debugPrint('RTC_LIVE: account ${i + 1} authenticated');
    }
    stage = 'private room creation';
    roomId = await clients.first.createGroupChat(
      groupName: 'SeND RTC temporary interoperability test',
      enableEncryption: true,
      invite: accounts
          .skip(1)
          .take(participantCount - 1)
          .map((row) => row[0])
          .toList(),
      groupCall: true,
      powerLevelContentOverride: {
        'events': {rtcCallMemberType: 0},
      },
    );
    for (final client in clients) {
      if (client != clients.first) await client.joinRoom(roomId);
      await client
          .waitForRoomInSync(roomId, join: true)
          .timeout(const Duration(seconds: 30));
    }
    debugPrint('RTC_LIVE: private encrypted room ready');
    await browser?.start(accounts[2][0], accounts[2][1], roomId);
    for (var i = 0; i < clients.length; i++) {
      stage = 'account ${i + 1} SFU join';
      final client = clients[i];
      final room = client.getRoomById(roomId)!;
      final api = RtcTransportApi(client);
      final focuses = await api.discover();
      if (focuses.isEmpty) throw StateError('No MatrixRTC transport');
      final session = RtcSfuSession(
        matrixRoom: room,
        transport: focuses.first,
        api: api,
        preferences: const AppPreferences(outputVolume: 0, callSound: false),
        deafened: true,
        onProgress: (value) =>
            debugPrint('RTC_LIVE_STAGE: participant ${i + 1}, $value'),
      );
      sessions.add(session);
      await session.start().timeout(const Duration(seconds: 45));
      debugPrint('RTC_LIVE: participant ${i + 1} joined');
    }
    stage = 'encrypted media exchange';
    final deadline = DateTime.now().add(
      Duration(seconds: browser == null ? 40 : 600),
    );
    var progress = 0;
    while (DateTime.now().isBefore(deadline)) {
      if (sessions.every(
            (s) =>
                s.members.length >= participantCount - 1 &&
                s.cryptoDiagnostics['ready']! >= participantCount,
          ) &&
          (browser == null ||
              (browser.result?['members'] == 2 &&
                  ((browser.result?['crypto'] as Map?)?['ready'] as int? ??
                          0) >=
                      3))) {
        break;
      }
      if (browser?.result?['error'] != null) {
        throw StateError('Browser call probe failed');
      }
      if (progress++ % 30 == 0) {
        for (var i = 0; i < sessions.length; i++) {
          debugPrint(
            'RTC_LIVE_WAIT: participant ${i + 1}, members ${sessions[i].members.length}, crypto ${sessions[i].cryptoDiagnostics}',
          );
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (browser != null &&
        (browser.result?['members'] != 2 ||
            ((browser.result?['crypto'] as Map?)?['ready'] as int? ?? 0) < 3)) {
      throw StateError('Browser encrypted media was not ready');
    }
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      debugPrint(
        'RTC_LIVE: participant ${i + 1}, members ${s.members.length}, crypto ${s.cryptoDiagnostics}',
      );
      if (s.members.length < participantCount - 1 ||
          s.cryptoDiagnostics['ready']! < participantCount) {
        throw StateError('Encrypted media was not ready');
      }
    }
    stage = 'membership renewal soak';
    final soakSeconds =
        int.tryParse(Platform.environment['RTC_SOAK_SECONDS'] ?? '') ?? 0;
    for (var second = 0; second < soakSeconds; second++) {
      if (sessions.any((s) => s.members.length != participantCount - 1)) {
        throw StateError('Membership expired during an active call');
      }
      if (second % 30 == 0) {
        debugPrint('RTC_LIVE: membership renewal stable at ${second}s');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    stage = 'mute and deafen';
    await sessions.first.setMuted(true);
    if (sessions.first.microphoneTrackEnabled ||
        sessions.first.inputLevel != 0) {
      throw StateError('Microphone mute gate failed');
    }
    if (!sessions.every((s) => s.remoteAudioDisabled)) {
      throw StateError('Deafen gate failed');
    }
    await sessions.first.setMuted(false);
    if (!sessions.first.microphoneTrackEnabled) {
      throw StateError('Microphone unmute failed');
    }
    debugPrint('RTC_LIVE: mute, unmute and deafen gates passed');
    stage = 'transport reconnect';
    for (final full in [false, true]) {
      // This operator-run tool is a live integration test, not application UI.
      // ignore: invalid_use_of_visible_for_testing_member
      await sessions.first.simulateTransportReconnect(full: full);
      await Future<void>.delayed(const Duration(seconds: 2));
      final until = DateTime.now().add(const Duration(seconds: 40));
      while (sessions.first.status != VoiceConnectionStatus.connected &&
          DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (sessions.first.status != VoiceConnectionStatus.connected ||
          !sessions.first.microphoneTrackEnabled ||
          !sessions.first.remoteAudioDisabled) {
        throw StateError('Reconnect did not restore media gates');
      }
      debugPrint('RTC_LIVE: ${full ? "full" : "signal"} reconnect passed');
    }
    if (browser != null) {
      stage = 'browser synthetic camera';
      browser.requestCamera = true;
      final until = DateTime.now().add(const Duration(seconds: 40));
      var videoReady = false;
      while (DateTime.now().isBefore(until)) {
        final streams = sessions.first.mediaStreams
            .where((s) => !s.local)
            .toList();
        if (streams.isNotEmpty && renderers.isEmpty) {
          final renderer = RTCVideoRenderer();
          renderers.add(renderer);
          await renderer.initialize();
          renderer.srcObject = streams.first.stream;
        }
        if (renderers.isNotEmpty &&
            renderers.first.videoWidth > 0 &&
            renderers.first.videoHeight > 0 &&
            sessions.first.cryptoDiagnostics['failed'] == 0) {
          videoReady = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      if (!videoReady) {
        throw StateError('Browser camera did not decode natively');
      }
      debugPrint(
        'RTC_LIVE: synthetic browser camera decrypted and rendered natively',
      );
    }
    success = true;
  } catch (error) {
    // SDK/native diagnostics are separately suppressed. Do not print server
    // responses, credentials, JWTs, room keys or recovery keys here.
    debugPrint(
      'RTC_LIVE_FAILED: $stage (${error is MatrixException ? error.errcode : error.runtimeType})',
    );
  } finally {
    for (final renderer in renderers) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    await browser?.close();
    for (final session in sessions.reversed) {
      try {
        await session.close();
      } catch (_) {}
    }
    for (final client in clients.reversed) {
      if (roomId != null) {
        try {
          await client.leaveRoom(roomId);
        } catch (_) {}
      }
      try {
        // No persistent store or backup changes exist in this test.
        await client.abortSync();
        await client.request(RequestType.POST, '/client/v3/logout', data: {});
      } catch (_) {}
      try {
        await client.dispose();
      } catch (_) {}
    }
    debugPrint(
      'RTC_LIVE: test-room participants left and temporary sessions logged out',
    );
  }
  debugPrint(success ? 'RTC_LIVE_PROBE_OK' : 'RTC_LIVE_PROBE_FAILED');
  exit(success ? 0 : 1);
}
