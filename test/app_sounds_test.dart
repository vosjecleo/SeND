import 'package:deltiecord/services/app_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all voice and control cues use the v3 sound pack', () async {
    final playback = _FakePlayback();
    AppSounds.replacePlaybackForTesting(playback);
    AppSounds.callVolume = 1;
    await AppSounds.callConnected();
    await AppSounds.participantLeft();
    await AppSounds.callDisconnected();
    await AppSounds.muteChanged(true);
    await AppSounds.muteChanged(false);
    await AppSounds.deafenChanged(true);
    await AppSounds.deafenChanged(false);
    expect(playback.assets.map((uri) => uri.split('/').last), [
      'vc_join.wav',
      'vc_leave.wav',
      'vc_disconnect.wav',
      'mute.wav',
      'unmute.wav',
      'deafen.wav',
      'undeafen.wav',
    ]);
  });

  testWidgets('ringtone loops but is capped at thirty seconds', (tester) async {
    final playback = _FakePlayback();
    AppSounds.replacePlaybackForTesting(playback);
    AppSounds.callVolume = .5;
    await AppSounds.startRingtone(duration: const Duration(minutes: 2));
    expect(playback.loops, [true]);
    expect(playback.volumes, [.5]);
    await tester.pump(const Duration(seconds: 29));
    expect(playback.stopped, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(playback.stopped, ['asset:///assets/audio/ringtone.wav']);
    AppSounds.callVolume = 1;
  });

  testWidgets(
    'answer/hangup stops ringing immediately without a later replay',
    (tester) async {
      final playback = _FakePlayback();
      AppSounds.replacePlaybackForTesting(playback);
      await AppSounds.startRingtone();
      await AppSounds.stopRingtone();
      await tester.pump(const Duration(seconds: 60));
      expect(playback.assets, hasLength(1));
      expect(playback.stopped, hasLength(1));
    },
  );

  test('sound service creates playback and releases it', () async {
    AppSounds.notificationVolume = 1;
    AppSounds.callVolume = 1;
    final playback = _FakePlayback();
    AppSounds.replacePlaybackForTesting(playback);

    await AppSounds.notification();
    await AppSounds.callConnected();
    await AppSounds.callDisconnected();
    await AppSounds.dispose();

    expect(playback.assets, [
      'asset:///assets/audio/notification.wav',
      'asset:///assets/audio/vc_join.wav',
      'asset:///assets/audio/vc_disconnect.wav',
    ]);
    expect(playback.disposed, isTrue);
  });
  test(
    'notification and call volumes are independent, and zero is silent',
    () async {
      final playback = _FakePlayback();
      AppSounds.replacePlaybackForTesting(playback);
      AppSounds.notificationVolume = .25;
      AppSounds.callVolume = .75;
      await AppSounds.notification();
      await AppSounds.callConnected();
      expect(playback.volumes, [.25, .75]);
      AppSounds.notificationVolume = 0;
      await AppSounds.notification();
      expect(playback.assets, hasLength(2));
      AppSounds.notificationVolume = 1;
      AppSounds.callVolume = 1;
    },
  );
}

class _FakePlayback implements AppSoundPlayback {
  final assets = <String>[];
  final volumes = <double>[];
  bool disposed = false;
  final loops = <bool>[];
  final stopped = <String>[];

  @override
  Future<void> play(
    String assetUri, {
    double volume = 1,
    bool loop = false,
  }) async {
    assets.add(assetUri);
    volumes.add(volume);
    loops.add(loop);
  }

  @override
  Future<void> stop(String assetUri) async => stopped.add(assetUri);

  @override
  Future<void> dispose() async => disposed = true;
}
