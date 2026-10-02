import 'package:deltiecord/services/rtc_audio_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

class _Track extends Fake implements MediaStreamTrack {
  _Track(this.kind);
  @override
  final String kind;
  @override
  bool enabled = true;
}

void main() {
  test(
    'microphone mute disables audio but never video; unmute restores it',
    () {
      final mic = _Track('audio');
      final peerMicrophone = _Track('audio');
      final camera = _Track('video');
      setRtcAudioMuted([mic, peerMicrophone, camera], true);
      expect(mic.enabled, isFalse);
      expect(peerMicrophone.enabled, isFalse);
      expect(camera.enabled, isTrue);
      setRtcAudioMuted([mic, peerMicrophone, camera], false);
      expect(mic.enabled, isTrue);
      expect(peerMicrophone.enabled, isTrue);
    },
  );

  test(
    'deafen gates voice and shared audio even without native gain',
    () async {
      final voice = _Track('audio');
      final shared = _Track('audio');
      final video = _Track('video');
      final volumes = <double>[];
      Future<void> unavailable(double gain, MediaStreamTrack track) async {
        volumes.add(gain);
        throw UnsupportedError('per-track gain');
      }

      await applyRtcRemoteAudio(
        tracks: [voice, shared, video],
        muted: true,
        volume: .6,
        setVolume: unavailable,
      );
      expect(voice.enabled, isFalse);
      expect(shared.enabled, isFalse);
      expect(video.enabled, isTrue);
      expect(volumes, [0, 0]);
      await applyRtcRemoteAudio(
        tracks: [voice, shared],
        muted: false,
        volume: .6,
        setVolume: unavailable,
      );
      expect(voice.enabled, isTrue);
      expect(shared.enabled, isTrue);
      expect(volumes, [0, 0, .6, .6]);
    },
  );

  test('zero output volume silences tracks without gain support', () async {
    final track = _Track('audio');
    await applyRtcRemoteAudio(
      tracks: [track],
      muted: false,
      volume: 0,
      setVolume: (_, _) async => throw UnsupportedError('gain'),
    );
    expect(track.enabled, isFalse);
  });

  test('stale active speaker cannot light a muted or silent local avatar', () {
    for (final muted in [true, false]) {
      expect(
        rtcParticipantSpeaking(
          local: true,
          muted: muted,
          inputLevel: muted ? 1 : 0,
          activeSpeaker: true,
        ),
        isFalse,
      );
    }
    expect(
      rtcParticipantSpeaking(
        local: true,
        muted: false,
        inputLevel: .2,
        activeSpeaker: false,
      ),
      isTrue,
    );
    expect(
      rtcParticipantSpeaking(
        local: false,
        muted: true,
        inputLevel: 0,
        activeSpeaker: true,
      ),
      isTrue,
    );
  });
}
