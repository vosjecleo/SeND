import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/frame_diagnostics.dart';

void main() {
  test('frame diagnostics report aggregate durations only', () {
    final frame = FrameTiming(
      vsyncStart: 1000,
      buildStart: 3000,
      buildFinish: 8000,
      rasterStart: 9000,
      rasterFinish: 19000,
      rasterFinishWallTime: 19000,
    );
    expect(
      frameTimingSummary([frame]),
      'SeND frames n=1 build_p95_ms=5.0 raster_p95_ms=10.0 vsync_p95_ms=2.0 total_p95_ms=18.0',
    );
    expect(frameTimingSummary([]), contains('n=0'));
  });
}
