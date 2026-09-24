import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/voice_recording.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/voice_message_composer.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'widget_test.dart' show FakeBackend;

class _SendBackend extends FakeBackend {
  bool fail = true;
  int attempts = 0;
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    attempts++;
    expect(roomId, '!voice:test');
    expect(attachment.voiceMessage, isTrue);
    if (fail) throw StateError('offline');
  }
}

class _Recorder implements VoiceRecorderDriver {
  final source = StreamController<double>.broadcast(sync: true);
  int disposed = 0;
  int paused = 0;
  bool denied = false;
  Completer<void>? starting;
  Uint8List bytes = Uint8List.fromList([
    0,
    0,
    0,
    20,
    102,
    116,
    121,
    112,
    77,
    52,
    65,
    32,
  ]);
  @override
  Stream<double> get levels => source.stream;
  @override
  Future<void> start() async {
    if (denied) throw StateError('denied');
    await starting?.future;
  }

  @override
  Future<void> pause() async {
    paused++;
  }

  @override
  Future<void> resume() async {
    paused--;
  }

  @override
  Future<({Uint8List bytes, String path})> stop() async =>
      (bytes: bytes, path: '/private/voice.m4a');
  @override
  Future<void> dispose() async {
    disposed++;
    await source.close();
  }
}

void main() {
  testWidgets('recording review never autosends and failed send can retry', (
    tester,
  ) async {
    final backend = _SendBackend();
    final driver = _Recorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: VoiceMessageComposer(
            backend: backend,
            roomId: '!voice:test',
            createRecording: () =>
                VoiceRecordingController(createDriver: () => driver),
            builder: (start) =>
                TextButton(onPressed: start, child: const Text('Record')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pump();
    await tester.tap(find.byTooltip('Pause recording'));
    await tester.pump();
    expect(find.byTooltip('Resume recording'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Stop recording'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(backend.attempts, 0);
    expect(find.byTooltip('Play recording'), findsOneWidget);
    await tester.tap(find.byTooltip('Send voice message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('retry or delete'), findsOneWidget);
    expect(driver.disposed, 0);
    backend.fail = false;
    await tester.tap(find.byTooltip('Send voice message'));
    await tester.pumpAndSettle();
    expect(backend.attempts, 2);
    expect(find.text('Record'), findsOneWidget);
    // Stream cancellation/disposal completes outside the fake frame clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(driver.disposed, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    backend.dispose();
  });
  test(
    'record/pause/resume/stop produces a bounded review draft, not a send',
    () async {
      final driver = _Recorder();
      final controller = VoiceRecordingController(createDriver: () => driver);
      await controller.start();
      expect(controller.state, VoiceRecordingState.recording);
      for (var i = 0; i < 7000; i++) {
        driver.source.add(i.isEven ? 0.5 : 1);
      }
      expect(controller.recentLevels.length, 80);
      await controller.togglePause();
      expect(controller.state, VoiceRecordingState.paused);
      driver.source.add(0);
      expect(controller.recentLevels.last, 1);
      await controller.togglePause();
      await controller.stop();
      expect(controller.state, VoiceRecordingState.ready);
      expect(controller.draft!.voiceMessage, isTrue);
      expect(controller.draft!.mimeType, 'audio/mp4');
      expect(controller.draft!.waveform!.length, lessThanOrEqualTo(256));
      expect(
        controller.draft!.waveform!.every((v) => v >= 0 && v <= 1024),
        isTrue,
      );
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(driver.disposed, 1);
    },
  );
  test('permission denial releases recorder and produces no draft', () async {
    final driver = _Recorder()..denied = true;
    final controller = VoiceRecordingController(createDriver: () => driver);
    await controller.start();
    expect(controller.state, VoiceRecordingState.failed);
    expect(controller.draft, isNull);
    expect(driver.disposed, 1);
    controller.dispose();
  });
  test(
    'disposing while permission is pending never starts UI timers',
    () async {
      final driver = _Recorder()..starting = Completer<void>();
      final controller = VoiceRecordingController(createDriver: () => driver);
      final start = controller.start();
      controller.dispose();
      driver.starting!.complete();
      await start;
      await Future<void>.delayed(Duration.zero);
      expect(driver.disposed, 1);
      expect(controller.draft, isNull);
    },
  );
  test('rejects oversize recording and unknown containers', () async {
    expect(() => recordingFormat(Uint8List(12)), throwsStateError);
    expect(
      recordingFormat(Uint8List.fromList([0x1a, 0x45, 0xdf, 0xa3])).mime,
      'audio/webm',
    );
    expect(
      recordingFormat(Uint8List.fromList([79, 103, 103, 83])).mime,
      'audio/ogg',
    );
    final driver = _Recorder()..bytes = Uint8List(voiceRecordingLimit + 1);
    final controller = VoiceRecordingController(createDriver: () => driver);
    await controller.start();
    await controller.stop();
    expect(controller.state, VoiceRecordingState.failed);
    expect(controller.draft, isNull);
    controller.dispose();
  });
}
