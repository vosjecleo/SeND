import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

const uiDiagnosticsEnabled = bool.fromEnvironment('SEND_INPUT_DIAGNOSTICS');
final _events = <String, int>{};
final _sources = <String, String>{};

void countUiDiagnostic(String event, {StackTrace Function()? source}) {
  if (!uiDiagnosticsEnabled) return;
  _events.update(event, (value) => value + 1, ifAbsent: () => 1);
  if (source != null && !_sources.containsKey(event)) {
    _sources[event] = source()
        .toString()
        .split('\n')
        .skip(1)
        .take(5)
        .map((line) => line.split('(').first.trim())
        .join(' / ');
  }
}

String frameTimingSummary(List<FrameTiming> frames) {
  double p95(Duration Function(FrameTiming) read) {
    final values = frames.map((f) => read(f).inMicroseconds).toList()..sort();
    return values.isEmpty
        ? 0
        : values[((values.length - 1) * .95).ceil()] / 1000;
  }

  return 'SeND frames n=${frames.length} '
      'build_p95_ms=${p95((f) => f.buildDuration).toStringAsFixed(1)} '
      'raster_p95_ms=${p95((f) => f.rasterDuration).toStringAsFixed(1)} '
      'vsync_p95_ms=${p95((f) => f.vsyncOverhead).toStringAsFixed(1)} '
      'total_p95_ms=${p95((f) => f.totalSpan).toStringAsFixed(1)}';
}

/// Local diagnostic builds only. No message, account or clipboard contents.
void enableFrameDiagnostics() {
  if (!uiDiagnosticsEnabled) return;
  final clock = Stopwatch()..start();
  final frames = <FrameTiming>[];
  SchedulerBinding.instance.addTimingsCallback((batch) {
    frames.addAll(batch);
    if (frames.length > 240) frames.removeRange(0, frames.length - 240);
    if (clock.elapsedMilliseconds < 2000) return;
    debugPrint(frameTimingSummary(frames));
    for (final event in _events.entries) {
      debugPrint(
        'SeND ui event=${event.key} count=${event.value} source=${_sources[event.key] ?? '-'}',
      );
    }
    _events.clear();
    _sources.clear();
    frames.clear();
    clock.reset();
  });
}
