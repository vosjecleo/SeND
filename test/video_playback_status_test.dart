import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/ui/video_playback_status.dart';

void main() {
  testWidgets('EOF shows Play even if backend leaves playing true', (
    tester,
  ) async {
    final playing = StreamController<bool>.broadcast();
    final completed = StreamController<bool>.broadcast();
    addTearDown(playing.close);
    addTearDown(completed.close);
    await tester.pumpWidget(
      MaterialApp(
        home: VideoPlaybackStatus(
          playing: playing.stream,
          completed: completed.stream,
          initialPlaying: true,
          initialCompleted: false,
          builder: (_, active) => Text(active ? 'Pause' : 'Play'),
        ),
      ),
    );
    expect(find.text('Pause'), findsOneWidget);
    completed.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    playing.add(true);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
    completed.add(false);
    await tester.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget);
    playing.add(false);
    await tester.pumpAndSettle();
    expect(find.text('Play'), findsOneWidget);
  });
}
