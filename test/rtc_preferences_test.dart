import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RTC device and per-participant choices survive preference copies', () {
    final preferences = const AppPreferences().copyWith(
      preferredAudioInputId: 'microphone-1',
      preferredAudioOutputId: 'headphones-1',
      preferredCameraId: 'camera-1',
      participantVolumes: const {'@friend:example.org': 0.42},
    );
    final updated = preferences.copyWith(fontScale: 1.1);

    expect(updated.preferredAudioInputId, 'microphone-1');
    expect(updated.preferredAudioOutputId, 'headphones-1');
    expect(updated.preferredCameraId, 'camera-1');
    expect(updated.participantVolumes['@friend:example.org'], 0.42);
  });
}
