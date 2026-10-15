import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

Future<void> setSfuAudioGain(
  String id,
  rtc.MediaStreamTrack track,
  double gain,
) async {
  try {
    await rtc.Helper.setVolume(gain.clamp(0, 1), track);
  } catch (_) {}
}
