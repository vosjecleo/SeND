import 'package:deltiecord/services/app_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      'asset:///assets/audio/call-connected.wav',
      'asset:///assets/audio/call-disconnected.wav',
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

  @override
  Future<void> play(String assetUri, {double volume = 1}) async {
    assets.add(assetUri);
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async => disposed = true;
}
