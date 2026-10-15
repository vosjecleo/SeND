import 'dart:async';
import 'package:deltiecord/matrix/matrix_voice_controller.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:deltiecord/matrix/rtc/rtc_sfu_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_transport_api.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Api extends RtcTransportApi {
  _Api(super.client, this.result);
  final Future<List<RtcTransport>> result;
  @override
  Future<List<RtcTransport>> discover() => result;
}

class _Session extends RtcSfuSession {
  _Session({
    required super.matrixRoom,
    required super.transport,
    required super.preferences,
    required super.api,
  });
  final began = Completer<void>();
  final joinGate = Completer<void>();
  Completer<void>? closeGate;
  int closes = 0;
  @override
  Future<void> start() async {
    began.complete();
    await joinGate.future;
    status = VoiceConnectionStatus.connected;
  }

  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
  }

  @override
  Future<void> setMuted(bool value) async {
    muted = value;
  }

  @override
  void applyRemoteAudio({
    required bool deafen,
    required Set<String> locallyMutedUsers,
    required Map<String, double> participantVolumes,
  }) {
    deafened = deafen;
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late MatrixVoiceController controller;
  late _Api api;
  late List<_Session> sessions;
  final transport = RtcTransport(
    serviceUrl: Uri.parse('https://rtc.example.org'),
  );
  setUp(() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final sdk = await MatrixSdkDatabase.init(
      'rtc-lifecycle',
      database: db,
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('rtc-lifecycle', database: sdk);
    client.rooms.add(Room(id: '!call:example.org', client: client));
    api = _Api(client, Future.value([transport]));
    sessions = [];
    controller = MatrixVoiceController(
      client,
      friendlyError: (_) => 'Call unavailable',
      canRingRoom: (_) => false,
      transportApiFactory: (_) => api,
      sessionFactory: (room, focus, prefs, api) {
        final s = _Session(
          matrixRoom: room,
          transport: focus,
          preferences: prefs,
          api: api,
        );
        sessions.add(s);
        return s;
      },
    );
    controller.applyPreferences(const AppPreferences(callSound: false));
  });
  tearDown(() async {
    for (final s in sessions) {
      if (!s.joinGate.isCompleted) s.joinGate.complete();
      if (s.closeGate case final gate? when !gate.isCompleted) gate.complete();
    }
    await controller.leave();
    controller.dispose();
    await client.dispose();
  });

  test('missing SFU fails without a mesh fallback', () async {
    api = _Api(client, Future.value([]));
    await controller.join('!call:example.org');
    expect(sessions, isEmpty);
    expect(controller.status, VoiceConnectionStatus.error);
    expect(controller.activeRoomId, isNull);
  });

  test('leave cancels discovery before capture is created', () async {
    final gate = Completer<List<RtcTransport>>();
    api = _Api(client, gate.future);
    final joining = controller.join('!call:example.org');
    await settle();
    await controller.leave();
    gate.complete([transport]);
    await joining;
    expect(sessions, isEmpty);
    expect(controller.status, VoiceConnectionStatus.disconnected);
  });

  test('leave during join cannot revive the call', () async {
    final joining = controller.join('!call:example.org');
    await settle();
    final s = sessions.single;
    await s.began.future;
    await controller.leave();
    s.joinGate.complete();
    await joining;
    expect(s.closes, greaterThanOrEqualTo(1));
    expect(controller.activeRoomId, isNull);
    expect(controller.status, VoiceConnectionStatus.disconnected);
  });

  test(
    'mute and deafen reach the active session and survive reconnect',
    () async {
      final joining = controller.join('!call:example.org');
      await settle();
      sessions.single.joinGate.complete();
      await joining;
      await controller.setMuted(true);
      await controller.setDeafened(true);
      expect(sessions.single.muted, isTrue);
      expect(sessions.single.deafened, isTrue);
      final changing = controller.selectAudioInput('replacement-microphone');
      await settle();
      expect(sessions, hasLength(2));
      expect(sessions.last.muted, isTrue);
      expect(sessions.last.deafened, isTrue);
      sessions.last.joinGate.complete();
      await changing;
      expect(controller.status, VoiceConnectionStatus.connected);
    },
  );

  test('new join waits for overlapping leaves to finish', () async {
    final joining = controller.join('!call:example.org');
    await settle();
    sessions.single.joinGate.complete();
    await joining;
    final old = sessions.single..closeGate = Completer<void>();
    final leaving = controller.leave();
    final secondLeave = controller.leave();
    final rejoining = controller.join('!call:example.org');
    await settle();
    expect(sessions, hasLength(1));
    old.closeGate!.complete();
    await Future.wait([leaving, secondLeave]);
    await settle();
    expect(sessions, hasLength(2));
    sessions.last.joinGate.complete();
    await rejoining;
    expect(old.closes, 1);
    expect(controller.status, VoiceConnectionStatus.connected);
  });
}
