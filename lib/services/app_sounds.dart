import 'package:media_kit/media_kit.dart';

/// Playback boundary for short in-app sounds.
///
/// Desktop `SystemSound` APIs are not implemented consistently on Linux and
/// may never create an audio stream. SeND therefore uses its existing
/// media engine, while keeping failures non-fatal to messaging and RTC state.
abstract interface class AppSoundPlayback {
  Future<void> play(String assetUri, {double volume = 1});

  Future<void> dispose();
}

final class MediaKitAppSoundPlayback implements AppSoundPlayback {
  final _players = <bool, Player>{};
  bool _disposed = false;

  @override
  Future<void> play(String assetUri, {double volume = 1}) async {
    if (_disposed) return;
    if (volume <= 0) return;
    final category = assetUri.endsWith('/notification.wav');
    final player = _players.putIfAbsent(category, Player.new);
    await player.setVolume(volume.clamp(0, 1) * 100);
    await player.open(Media(assetUri), play: true);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
  }
}

abstract final class AppSounds {
  static double notificationVolume = 1;
  static double callVolume = 1;
  static AppSoundPlayback _playback = MediaKitAppSoundPlayback();

  static Future<void> notification() =>
      _play('asset:///assets/audio/notification.wav');

  static Future<void> callConnected() =>
      _play('asset:///assets/audio/call-connected.wav');

  static Future<void> callDisconnected() =>
      _play('asset:///assets/audio/call-disconnected.wav');

  static Future<void> _play(String assetUri) async {
    try {
      final volume = assetUri.endsWith('/notification.wav')
          ? notificationVolume
          : callVolume;
      if (volume <= 0) return;
      await _playback.play(assetUri, volume: volume.clamp(0, 1));
    } catch (_) {
      // A missing/unsupported audio backend must not alter app or RTC state.
    }
  }

  static Future<void> dispose() => _playback.dispose();

  /// Replaces the output in tests without initializing native media plugins.
  static void replacePlaybackForTesting(AppSoundPlayback playback) {
    _playback = playback;
  }
}
