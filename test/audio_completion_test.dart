import 'dart:async';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/audio_attachment_player.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'widget_test.dart' show FakeBackend;

class _Backend extends FakeBackend {
  @override
  Future<MediaPlaybackSource?> getMediaPlaybackSource(String messageId) async =>
      MediaPlaybackSource(
        uri: Uri.parse('file:///test.ogg'),
        headers: const {},
      );
}

class _Streams extends Fake implements PlayerStream {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final completions = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<Duration> get position => positions.stream;
  @override
  Stream<bool> get completed => completions.stream;
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
}

class _Player extends Fake implements Player {
  @override
  final _Streams stream = _Streams();
  @override
  PlayerState state = const PlayerState();
  @override
  Future<void> open(Playable playable, {bool play = true}) async {}
  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(completed: false);
    stream.positions.add(position);
    stream.completions.add(false);
  }

  @override
  Future<void> play() async {}
  @override
  Future<void> dispose() async {
    await stream.positions.close();
    await stream.completions.close();
  }
}

void main() {
  testWidgets(
    'EOF fills the waveform despite late position; replay and seek reset it',
    (tester) async {
      final player = _Player();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: AudioAttachmentPlayer(
              backend: _Backend(),
              messageId: 'audio',
              onSave: () {},
              createPlayer: () => player,
              attachment: const ChatAttachment(
                kind: AttachmentKind.audio,
                name: 'voice.ogg',
                mimeType: 'audio/ogg',
                size: 100,
                encrypted: false,
                spoiler: false,
                voiceMessage: true,
                durationMilliseconds: 4000,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Play audio'));
      await tester.pumpAndSettle();
      AudioProgress progress() =>
          tester.widget<AudioProgress>(find.byType(AudioProgress));
      player.stream.positions.add(const Duration(milliseconds: 3980));
      await tester.pump();
      expect(progress().position, const Duration(milliseconds: 3980));
      player.state = player.state.copyWith(completed: true);
      player.stream.completions.add(true);
      player.stream.positions.add(const Duration(milliseconds: 3985));
      await tester.pump();
      expect(progress().position, const Duration(seconds: 4));
      await tester.tap(find.byTooltip('Play audio'));
      await tester.pumpAndSettle();
      expect(progress().position, Duration.zero);
      player.stream.completions.add(true);
      await tester.pump();
      progress().onSeek!(const Duration(seconds: 2));
      await tester.pump();
      expect(progress().position, const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
