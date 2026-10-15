import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<void> setSfuAudioGain(
  String id,
  rtc.MediaStreamTrack track,
  double gain,
) async {
  // LiveKit 2.13.1 owns these playback elements. Adjust its existing audio
  // output rather than starting a second renderer for the same remote track.
  final element = web.document.getElementById('livekit_audio_$id');
  if (element != null && element.isA<web.HTMLAudioElement>()) {
    final audio = element as web.HTMLAudioElement;
    audio.volume = gain.clamp(0, 1);
    audio.muted = gain <= 0;
  }
}
