import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/video_seek_controller.dart';
import 'package:deltiecord/services/video_byte_range.dart';
import 'package:deltiecord/ui/video_playback_overlay.dart';

void main() {
  test('seek position does not snap to stale decoder ticks', () async {
    final calls = <Duration>[];
    final seek = VideoSeekController(
      seek: (value) async => calls.add(value),
      initialPosition: const Duration(seconds: 10),
      initialDuration: const Duration(seconds: 100),
    );
    addTearDown(seek.dispose);
    await seek.seekTo(const Duration(seconds: 70));
    seek.update(position: const Duration(seconds: 11), duration: Duration.zero);
    expect(seek.position.inSeconds, 70);
    expect(seek.duration.inSeconds, 100);
    seek.update(position: const Duration(seconds: 70));
    expect(seek.position.inSeconds, 70);
    expect(calls.single.inSeconds, 70);
  });
  test(
    'rapid skips coalesce while a seek is in flight and clamp at endpoints',
    () async {
      final gate = Completer<void>();
      final calls = <Duration>[];
      final seek = VideoSeekController(
        seek: (value) async {
          calls.add(value);
          if (calls.length == 1) await gate.future;
        },
        initialDuration: const Duration(seconds: 25),
      );
      addTearDown(seek.dispose);
      final first = seek.skip(10);
      final second = seek.skip(10);
      final third = seek.skip(10);
      expect(seek.position.inSeconds, 25);
      expect(calls.length, 1);
      gate.complete();
      await Future.wait([first, second, third]);
      expect(calls.map((d) => d.inSeconds), [10, 25]);
      await seek.skip(-100);
      expect(calls.last, Duration.zero);
    },
  );
  test(
    'failed and unknown-duration seeks never reset or restart playback',
    () async {
      final seek = VideoSeekController(
        seek: (_) async => throw StateError('Unavailable range'),
        initialPosition: const Duration(seconds: 30),
        initialDuration: const Duration(seconds: 100),
      );
      addTearDown(seek.dispose);
      await seek.skip(10);
      expect(seek.position.inSeconds, 30);
      var calls = 0;
      final unknown = VideoSeekController(seek: (_) async => calls++);
      addTearDown(unknown.dispose);
      await unknown.skip(10);
      expect(calls, 0);
    },
  );
  test('time labels cover seconds, minutes and hours', () {
    expect(videoTimeLabel(Duration.zero), '0:00');
    expect(videoTimeLabel(const Duration(seconds: 69)), '1:09');
    expect(videoTimeLabel(const Duration(seconds: 10709)), '2:58:29');
  });
  test('seek responses must match the requested range and declared size', () {
    bool valid(String? requested, int status, String? response, int length) =>
        matchesVideoByteRange(
          requested: requested,
          status: status,
          contentRange: response,
          contentLength: length,
        );
    expect(valid('bytes=16-31', 206, 'bytes 16-31/32', 16), true);
    expect(valid('bytes=16-', 206, 'bytes 16-31/32', 16), true);
    expect(valid('bytes=-16', 206, 'bytes 16-31/32', 16), true);
    expect(valid('bytes=16-31', 206, 'bytes 0-31/32', 32), false);
    expect(valid('bytes=16-31', 200, null, 32), false);
    expect(valid('bytes=16-31', 206, 'bytes 16-31/32', 15), false);
    expect(valid('bytes=16-31', 206, 'bytes 16-32/32', 17), false);
    expect(valid('bytes=-', 206, 'bytes 0-31/32', 32), false);
    expect(valid('bytes=0-31', 200, null, 32), true);
    expect(valid(null, 200, null, 32), true);
  });
}
