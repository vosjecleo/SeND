import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/audio_attachment_player.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  testWidgets('audio shows filename, waveform, times and explicit download', (
    tester,
  ) async {
    var saves = 0;
    const attachment = ChatAttachment(
      kind: AttachmentKind.audio,
      name: 'music.ogg',
      mimeType: 'audio/ogg',
      size: 1024,
      encrypted: false,
      spoiler: false,
      durationMilliseconds: 83000,
      waveform: [0, 512, 1024],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: AudioAttachmentPlayer(
            backend: FakeBackend(),
            messageId: 'audio',
            attachment: attachment,
            onSave: () => saves++,
          ),
        ),
      ),
    );
    expect(find.text('music.ogg'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('01:23'), findsOneWidget);
    expect(find.byType(AudioProgress), findsOneWidget);
    await tester.tap(find.byTooltip('Download audio'));
    expect(saves, 1);
  });

  testWidgets('voice messages hide filenames but retain timing and download', (
    tester,
  ) async {
    const attachment = ChatAttachment(
      kind: AttachmentKind.audio,
      name: 'voice.ogg',
      mimeType: 'audio/ogg',
      size: 100,
      encrypted: false,
      spoiler: false,
      voiceMessage: true,
      durationMilliseconds: 4000,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: AudioAttachmentPlayer(
            backend: FakeBackend(),
            messageId: 'voice',
            attachment: attachment,
            onSave: () {},
          ),
        ),
      ),
    );
    expect(find.text('voice.ogg'), findsNothing);
    expect(find.text('00:04'), findsOneWidget);
    expect(find.byTooltip('Download audio'), findsOneWidget);
  });

  testWidgets('waveform seeks by position', (tester) async {
    Duration? seek;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: AudioProgress(
              position: const Duration(seconds: 10),
              duration: const Duration(seconds: 100),
              waveform: const [],
              onSeek: (value) => seek = value,
            ),
          ),
        ),
      ),
    );
    final bar = find.descendant(
      of: find.byType(AudioProgress),
      matching: find.byType(GestureDetector),
    );
    await tester.tapAt(tester.getTopLeft(bar) + const Offset(100, 20));
    expect(seek, const Duration(seconds: 50));
    expect(
      audioTime(const Duration(hours: 2, minutes: 3, seconds: 4)),
      '2:03:04',
    );
  });
}
