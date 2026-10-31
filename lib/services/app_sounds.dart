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

abstract interface class AppSoundVoice {
  Stream<bool> get completed;
  Future<void> open(String uri, {required bool loop});
  Future<void> setGain(double gain);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

final class _MediaKitSoundVoice implements AppSoundVoice {
  final _player = Player();
  @override
  Stream<bool> get completed => _player.stream.completed;
  @override
  Future<void> open(String uri, {required bool loop}) async {
    await _player.setPlaylistMode(
      loop ? PlaylistMode.single : PlaylistMode.none,
    );
    await _player.open(Media(uri), play: false);
  }

  @override
  Future<void> setGain(double gain) =>
      _player.setVolume(gain.clamp(0, 1) * 100);
  @override
  Future<void> play() => _player.play();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> dispose() => _player.dispose();
}

final class MediaKitAppSoundPlayback implements AppSoundPlayback {
  MediaKitAppSoundPlayback({
    AppSoundVoice Function()? createVoice,
    Future<void> Function(Duration)? delay,
  }) : _createVoice = createVoice ?? _MediaKitSoundVoice.new,
       _delay = delay ?? ((duration) => Future<void>.delayed(duration));
  final AppSoundVoice Function() _createVoice;
  final Future<void> Function(Duration) _delay;
  final _players = <String, AppSoundVoice>{};
  final _subscriptions = <String, StreamSubscription<bool>>{};
  final _generations = <String, int>{};
  final _playingGeneration = <String, int>{};
  final _looping = <String, bool>{};
  final _requested = <String, double>{};
  final _gain = <String, double>{};
  Future<void> _pending = Future<void>.value();
  bool _disposed = false;

  String _category(String uri) => uri.endsWith('/ringtone.wav')
      ? 'ringtone'
      : uri.endsWith('/notification.wav')
      ? 'notification'
      : 'voice';

  Future<void> _queue(Future<void> Function() action) {
    if (_disposed) return Future<void>.value();
    final next = _pending
        .catchError((_) {})
        .then((_) => _disposed ? Future<void>.value() : action());
    _pending = next;
    return next;
  }

  Future<void> _fadeMix() async {
    final total = _requested.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    final divisor = total > 1 ? total : 1.0;
    final start = {for (final key in _players.keys) key: _gain[key] ?? 0.0};
    final target = {
      for (final key in _players.keys) key: (_requested[key] ?? 0) / divisor,
    };
    if (start.keys.every(
      (key) => (start[key]! - target[key]!).abs() < .00001,
    )) {
      return;
    }
    for (var step = 1; step <= 4; step++) {
      final values = [
        for (final key in _players.keys)
          MapEntry(key, start[key]! + (target[key]! - start[key]!) * step / 4),
      ];
      // Lower gains first: intermediate native updates must retain headroom,
      // not just the final state of the mix.
      values.sort(
        (a, b) => (a.value - (_gain[a.key] ?? 0)).compareTo(
          b.value - (_gain[b.key] ?? 0),
        ),
      );
      for (final value in values) {
        await _players[value.key]!.setGain(value.value);
        _gain[value.key] = value.value;
      }
      await _delay(const Duration(milliseconds: 5));
    }
  }

  AppSoundVoice _voice(String category) => _players.putIfAbsent(category, () {
    final voice = _createVoice();
    _subscriptions[category] = voice.completed.listen((done) {
      if (!done || _looping[category] == true || _disposed) return;
      final generation = _playingGeneration[category];
      unawaited(
        _queue(() async {
          if (_playingGeneration[category] != generation ||
              _generations[category] != generation) {
            return;
          }
          _requested.remove(category);
          await _fadeMix();
        }).catchError((_) {}),
      );
    });
    return voice;
  });

  @override
  Future<void> play(
    String assetUri, {
    double volume = 1,
    bool loop = false,
  }) async {
    if (_disposed) return;
    if (volume <= 0) return;
    final category = _category(assetUri);
    final generation = (_generations[category] ?? 0) + 1;
    _generations[category] = generation;
    await _queue(() async {
      if (_generations[category] != generation) return;
      final player = _voice(category);
      _requested.remove(category);
      await _fadeMix();
      await player.stop();
      _gain[category] = 0;
      if (_disposed || _generations[category] != generation) return;
      await player.setGain(0);
      await player.open(assetUri, loop: loop);
      if (_disposed || _generations[category] != generation) return;
      _looping[category] = loop;
      _playingGeneration[category] = generation;
      _requested[category] = volume.clamp(0, 1);
      await player.play();
      await _fadeMix();
    });
  }

  @override
  Future<void> stop(String assetUri) {
    final category = _category(assetUri);
    final generation = (_generations[category] ?? 0) + 1;
    _generations[category] = generation;
    return _queue(() async {
      if (_generations[category] != generation) return;
      _requested.remove(category);
      try {
        await _fadeMix();
      } finally {
        await _players[category]?.stop();
        _gain[category] = 0;
      }
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _pending.catchError((_) {});
    _requested.clear();
    try {
      await _fadeMix();
    } catch (_) {}
    await Future.wait(
      _subscriptions.values.map((subscription) => subscription.cancel()),
    );
    await Future.wait(_players.values.map((player) => player.dispose()));
    _players.clear();
    _subscriptions.clear();
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

  static Future<void> previewRingtone() async {
    if (_ringTimer != null) return;
    await _play(_ringtone);
  }

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
