import 'package:deltiecord/matrix/matrix_voice_controller.dart';
import 'package:deltiecord/services/app_sounds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final eligible in [true, false]) {
    test('only an eligible DM/group chat can ring: $eligible', () async {
      final playback = _RingPlayback();
      AppSounds.replacePlaybackForTesting(playback);
      AppSounds.callVolume = 1;
      final client = await _testClient();
      client.setUserId('@me:test');
      final room = Room(id: '!call:test', client: client);
      final controller = MatrixVoiceController(
        client,
        friendlyError: (error) => error.toString(),
        canRingRoom: (_) => eligible,
      );
      final event = Event(
        type: RtcNotificationContent.eventType,
        eventId: r'$ring',
        senderId: '@caller:test',
        originServerTs: DateTime.now(),
        room: room,
        content: {
          ...RtcNotificationContent.create(
            type: RtcNotificationType.ring,
          ).toJson(),
          'm.mentions': {
            'user_ids': ['@me:test'],
          },
        },
      );
      controller.handleCallNotification(event);
      await Future<void>.delayed(Duration.zero);
      expect(controller.incomingCall?.roomId, eligible ? '!call:test' : null);
      expect(playback.rings, eligible ? 1 : 0);
      controller.handleCallNotification(event);
      expect(playback.rings, eligible ? 1 : 0);
      controller.dismissIncomingCall();
      controller.dispose();
      client.dispose();
    });
  }

  test(
    'old, untargeted, self and non-ringing RTC notifications stay silent',
    () async {
      final playback = _RingPlayback();
      AppSounds.replacePlaybackForTesting(playback);
      final client = await _testClient();
      client.setUserId('@me:test');
      final room = Room(id: '!call:test', client: client);
      final controller = MatrixVoiceController(
        client,
        friendlyError: (error) => '$error',
        canRingRoom: (_) => true,
      );
      for (final kind in ['old', 'untargeted', 'self', 'notification']) {
        final time = DateTime.now().subtract(
          Duration(minutes: kind == 'old' ? 2 : 0),
        );
        controller.handleCallNotification(
          Event(
            type: RtcNotificationContent.eventType,
            eventId: kind,
            senderId: kind == 'self' ? '@me:test' : '@caller:test',
            originServerTs: time,
            room: room,
            content: {
              ...RtcNotificationContent(
                senderTs: time,
                notificationType: kind == 'notification'
                    ? RtcNotificationType.notification
                    : RtcNotificationType.ring,
              ).toJson(),
              'm.mentions': {
                'user_ids': [kind == 'untargeted' ? '@other:test' : '@me:test'],
              },
            },
          ),
        );
      }
      expect(controller.incomingCall, isNull);
      expect(playback.rings, 0);
      controller.dispose();
      client.dispose();
    },
  );
  test('audio output selection reaches platform and updates state', () async {
    final selector = _FakeAudioOutputSelector();
    final client = await _testClient();
    final controller = MatrixVoiceController(
      client,
      friendlyError: (error) => error.toString(),
      audioOutputSelector: selector,
    );

    await controller.selectAudioOutput('headphones');

    expect(selector.selections, ['headphones']);
    expect(controller.selectedAudioOutputId, 'headphones');
    expect(controller.error, isNull);
    controller.dispose();
    client.dispose();
  });

  test('audio output failure is visible and does not change state', () async {
    final selector = _FakeAudioOutputSelector(error: StateError('missing'));
    final client = await _testClient();
    final controller = MatrixVoiceController(
      client,
      friendlyError: (error) => 'Audio output unavailable',
      audioOutputSelector: selector,
    );

    await controller.selectAudioOutput('missing-device');

    expect(controller.selectedAudioOutputId, isNull);
    expect(controller.error, 'Audio output unavailable');
    controller.dispose();
    client.dispose();
  });
}

class _RingPlayback implements AppSoundPlayback {
  int rings = 0;
  @override
  Future<void> play(
    String assetUri, {
    double volume = 1,
    bool loop = false,
  }) async {
    if (loop) rings++;
  }

  @override
  Future<void> stop(String assetUri) async {}
  @override
  Future<void> dispose() async {}
}

Future<Client> _testClient() async {
  sqfliteFfiInit();
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  final sdkDatabase = await MatrixSdkDatabase.init(
    'deltiecord-output-test',
    database: database,
    sqfliteFactory: databaseFactoryFfi,
  );
  return Client('deltiecord-output-test', database: sdkDatabase);
}

final class _FakeAudioOutputSelector implements RtcAudioOutputSelector {
  _FakeAudioOutputSelector({this.error});

  final Object? error;
  final selections = <String>[];

  @override
  Future<void> select(String deviceId) async {
    selections.add(deviceId);
    if (error != null) throw error!;
  }
}
