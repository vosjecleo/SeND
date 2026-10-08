import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'notification_volume.dart';

/// Playback boundary for short in-app sounds.
///
/// Desktop `SystemSound` APIs are not implemented consistently on Linux and
/// may never create an audio stream. SeND therefore uses its existing
/// media engine, while keeping failures non-fatal to messaging and RTC state.
abstract interface class AppSoundPlayback {
  Future<void> play(String assetUri, {double volume = 1, bool loop = false});

  Future<void> stop(String assetUri);

  Future<void> dispose();
}

final class MediaKitAppSoundPlayback implements AppSoundPlayback {
  final _players = <String, Player>{};
  final _pending = <String, Future<void>>{};
  bool _disposed = false;

  String _category(String uri) => uri.endsWith('/ringtone.wav')
      ? 'ringtone'
      : uri.endsWith('/notification.wav')
      ? 'notification'
      : 'voice';

  Future<void> _queue(String category, Future<void> Function() action) {
    final next = (_pending[category] ?? Future<void>.value())
        .catchError((_) {})
        .then((_) => _disposed ? Future<void>.value() : action());
    _pending[category] = next;
    return next;
  }

  @override
  Future<void> play(
    String assetUri, {
    double volume = 1,
    bool loop = false,
  }) async {
    if (_disposed) return;
    if (volume <= 0) return;
    final category = _category(assetUri);
    await _queue(category, () async {
      final player = _players.putIfAbsent(category, Player.new);
      await player.setVolume(volume.clamp(0, 1) * 100);
      await player.setPlaylistMode(
        loop ? PlaylistMode.single : PlaylistMode.none,
      );
      await player.open(Media(assetUri), play: true);
    });
  }

  @override
  Future<void> stop(String assetUri) => _queue(_category(assetUri), () async {
    await _players[_category(assetUri)]?.stop();
  });

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(
      _pending.values.map((pending) => pending.catchError((_) {})),
    );
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
  }
}

abstract final class AppSounds {
  static double notificationVolume = defaultNotificationVolume;
  static double callVolume = 1;
  static AppSoundPlayback _playback = MediaKitAppSoundPlayback();
  static Timer? _ringTimer;
  static const _ringtone = 'asset:///assets/audio/ringtone.wav';

  static Future<void> notification() =>
      _play('asset:///assets/audio/notification.wav');

  static Future<void> callConnected() =>
      _play('asset:///assets/audio/vc_join.wav');

  static Future<void> callDisconnected() =>
      _play('asset:///assets/audio/vc_disconnect.wav');

  static Future<void> participantLeft() =>
      _play('asset:///assets/audio/vc_leave.wav');
  static Future<void> muteChanged(bool muted) =>
      _play('asset:///assets/audio/${muted ? 'mute' : 'unmute'}.wav');
  static Future<void> deafenChanged(bool deafened) =>
      _play('asset:///assets/audio/${deafened ? 'deafen' : 'undeafen'}.wav');

  static Future<void> startRingtone({
    Duration duration = const Duration(seconds: 30),
  }) async {
    _ringTimer?.cancel();
    if (duration <= Duration.zero || callVolume <= 0) {
      await stopRingtone();
      return;
    }
    final limited = duration > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : duration;
    _ringTimer = Timer(limited, () => unawaited(stopRingtone()));
    try {
      await _playback.play(
        _ringtone,
        volume: callVolume.clamp(0, 1),
        loop: true,
      );
    } catch (_) {}
  }

  static Future<void> stopRingtone() async {
    if (_ringTimer == null) return;
    _ringTimer?.cancel();
    _ringTimer = null;
    try {
      await _playback.stop(_ringtone);
    } catch (_) {}
  }

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

  static Future<void> dispose() async {
    await stopRingtone();
    await _playback.dispose();
  }

  /// Replaces the output in tests without initializing native media plugins.
  static void replacePlaybackForTesting(AppSoundPlayback playback) {
    _ringTimer?.cancel();
    _ringTimer = null;
    _playback = playback;
  }
}
