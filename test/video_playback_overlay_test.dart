import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:deltiecord/ui/video_playback_overlay.dart';

class _Streams extends Fake implements PlayerStream {
  final positions = StreamController<Duration>.broadcast();
  final durations = StreamController<Duration>.broadcast();
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<Duration> get duration => durations.stream;
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
}

class _Player extends Fake implements Player {
  final events = _Streams();
  final seeks = <Duration>[];
  int toggles = 0;
  int plays = 0;
  bool completed = false;
  @override
  PlayerStream get stream => events;
  @override
  PlayerState get state => PlayerState(
    position: const Duration(seconds: 30),
    duration: const Duration(seconds: 120),
    playing: true,
    completed: completed,
  );
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> playOrPause() async => toggles++;
  @override
  Future<void> play() async => plays++;
  Future<void> close() async {
    await events.positions.close();
    await events.durations.close();
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Player player, {
    VoidCallback? fullscreen,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 220,
              child: VideoPlaybackOverlay(
                player: player,
                onFullscreen: fullscreen,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'shared player shows time and double taps seek in either direction',
    (tester) async {
      final player = _Player();
      addTearDown(player.close);
      var fullscreen = 0;
      await show(tester, player, fullscreen: () => fullscreen++);
      expect(find.text('0:30 / 2:00'), findsOneWidget);
      final rect = tester.getRect(find.byType(VideoPlaybackOverlay));
      Future<void> doubleTap(Offset point) async {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(point);
        await tester.pump();
      }

      await doubleTap(rect.topLeft + const Offset(40, 60));
      expect(player.seeks.last.inSeconds, 20);
      expect(find.text('−10s'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await doubleTap(rect.topLeft + const Offset(300, 60));
      expect(player.seeks.last.inSeconds, 30);
      expect(fullscreen, 0);
      expect(player.toggles, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
  testWidgets('scrubbing holds the thumb locally and commits only on release', (
    tester,
  ) async {
    final player = _Player();
    addTearDown(player.close);
    await show(tester, player);
    final slider = find.byKey(const ValueKey('video-seek-slider'));
    final rect = tester.getRect(slider);
    final drag = await tester.startGesture(
      Offset(rect.left + 80, rect.center.dy),
    );
    await drag.moveTo(Offset(rect.left + 220, rect.center.dy));
    await tester.pump();
    expect(player.seeks, isEmpty);
    final chosen = tester.widget<Slider>(slider).value;
    player.events.positions.add(Duration.zero);
    await tester.pump();
    expect(tester.widget<Slider>(slider).value, chosen);
    await drag.up();
    await tester.pump();
    expect(player.seeks.length, 1);
    expect(
      tester.widget<Slider>(slider).value,
      closeTo(player.seeks.single.inMilliseconds.toDouble(), 1),
    );
    expect(player.toggles, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'Play after an EOF seek keeps the selected position instead of replaying zero',
    (tester) async {
      final player = _Player()..completed = true;
      addTearDown(player.close);
      await show(tester, player);
      final slider = find.byKey(const ValueKey('video-seek-slider'));
      final rect = tester.getRect(slider);
      await tester.tapAt(Offset(rect.left + 180, rect.center.dy));
      await tester.pump();
      final target = player.seeks.last;
      expect(target, greaterThan(Duration.zero));
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(player.seeks.last, target);
      expect(player.seeks, isNot(contains(Duration.zero)));
      expect(player.plays, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
