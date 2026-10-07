import 'package:deltiecord/services/media_aspect_ratio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('video dimensions are used only as a complete positive pair', () {
    expect(mediaAspectRatio(1080, 1920), 9 / 16);
    expect(mediaAspectRatio(1080, null), 16 / 9);
    expect(mediaAspectRatio(null, 1920), 16 / 9);
    expect(mediaAspectRatio(0, 1920), 16 / 9);
    expect(mediaAspectRatio(null, 1920, fallback: 1), 1);
  });
}
