import 'package:webrtc_interface/webrtc_interface.dart';

/// Track enablement is the hard mute boundary. Volume is only a gain control
/// and is not implemented by every native audio backend.
void setRtcAudioMuted(Iterable<MediaStreamTrack> tracks, bool muted) {
  for (final track in tracks) {
    if (track.kind == 'audio') track.enabled = !muted;
  }
}

Future<void> applyRtcRemoteAudio({
  required Iterable<MediaStreamTrack> tracks,
  required bool muted,
  required double volume,
  required Future<void> Function(double, MediaStreamTrack) setVolume,
}) async {
  final audio = tracks.where((track) => track.kind == 'audio').toList();
  final gain = muted ? 0.0 : volume.clamp(0.0, 1.0);
  setRtcAudioMuted(audio, muted || gain == 0);
  for (final track in audio) {
    try {
      await setVolume(gain, track);
    } catch (_) {
      // Unsupported per-track gain must never defeat mute/deafen. The track
      // gate above still silences output, including shared desktop audio.
    }
  }
}

bool rtcParticipantSpeaking({
  required bool local,
  required bool muted,
  required double inputLevel,
  required bool activeSpeaker,
}) => local ? !muted && inputLevel >= 0.04 : activeSpeaker;
