import 'dart:async';
import 'package:deltiecord/services/app_sounds.dart';
import 'package:flutter_test/flutter_test.dart';

class _Voice implements AppSoundVoice {
  _Voice(this.checkMix);
  final void Function() checkMix;
  final completion = StreamController<bool>.broadcast(sync: true);
  final assets = <String>[];
  final gains = <double>[];
  double gain = 0;
  bool playing = false, disposed = false;
  @override
  Stream<bool> get completed => completion.stream;
  @override
  Future<void> setGain(double value) async {
    expect(value, inInclusiveRange(0, 1));
    gain = value;
    gains.add(value);
    checkMix();
  }

  @override
  Future<void> open(String uri, {required bool loop}) async {
    expect(
      gain,
      closeTo(0, 1e-9),
      reason: 'Opening a new stream must be silent',
    );
    assets.add(uri);
  }

  @override
  Future<void> play() async {
    expect(gain, closeTo(0, 1e-9));
    playing = true;
    checkMix();
  }

  @override
  Future<void> stop() async {
    expect(
      gain,
      closeTo(0, 1e-9),
      reason: 'Existing streams must fade before being stopped',
    );
    playing = false;
  }

  void finish() {
    playing = false;
    completion.add(true);
  }

  @override
  Future<void> dispose() async {
    expect(gain, closeTo(0, 1e-9));
    disposed = true;
    await completion.close();
  }
}

void main() {
  List<_Voice> voices = [];
  MediaKitAppSoundPlayback playback() => MediaKitAppSoundPlayback(
    delay: (_) async {},
    createVoice: () {
      final voice = _Voice(() {
        final sum = voices
            .where((v) => v.playing)
            .fold<double>(0, (sum, v) => sum + v.gain);
        expect(
          sum,
          lessThanOrEqualTo(1 + 1e-9),
          reason: 'No transient update may overdrive the cue mix',
        );
      });
      voices.add(voice);
      return voice;
    },
  );
  setUp(() => voices = []);

  test(
    'rapid control cues discard stale requests and fade before replacing audio',
    () async {
      final sound = playback();
      await sound.play('asset:///assets/audio/mute.wav');
      final voice = voices.single;
      final start = voice.gains.length;
      await Future.wait([
        sound.play('asset:///assets/audio/unmute.wav'),
        sound.play('asset:///assets/audio/deafen.wav'),
        sound.play('asset:///assets/audio/undeafen.wav'),
      ]);
      expect(voice.assets.map((uri) => uri.split('/').last), [
        'mute.wav',
        'undeafen.wav',
      ]);
      expect(voice.gains.skip(start).take(4), [.75, .5, .25, 0]);
      expect(voice.gain, closeTo(1, 1e-9));
      await sound.dispose();
      expect(voice.disposed, isTrue);
    },
  );

  test(
    'different cue channels may overlap without exceeding mix headroom',
    () async {
      final sound = playback();
      await sound.play('asset:///assets/audio/ringtone.wav', loop: true);
      await sound.play('asset:///assets/audio/notification.wav');
      await sound.play('asset:///assets/audio/mute.wav');
      expect(voices.where((v) => v.playing), hasLength(3));
      for (final voice in voices) {
        expect(voice.gain, closeTo(1 / 3, 1e-9));
      }
      await sound.stop('asset:///assets/audio/ringtone.wav');
      expect(voices.first.gain, 0);
      expect(voices[1].gain, closeTo(.5, 1e-9));
      expect(voices[2].gain, closeTo(.5, 1e-9));
      voices[1].finish();
      await Future<void>.delayed(Duration.zero);
      expect(voices[2].gain, closeTo(1, 1e-9));
      await sound.dispose();
    },
  );

  test('stopping a queued ringtone prevents delayed playback', () async {
    final sound = playback();
    await Future.wait([
      sound.play('asset:///assets/audio/ringtone.wav', loop: true),
      sound.stop('asset:///assets/audio/ringtone.wav'),
    ]);
    expect(voices, isEmpty);
    await sound.dispose();
  });
}
