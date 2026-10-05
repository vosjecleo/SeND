import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/audio_attachment_player.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/login_screen.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:deltiecord/ui/mobile/mobile_media.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:deltiecord/ui/rich_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'widget_test.dart' show FakeBackend;

void main() {
  test('legacy styles cannot reactivate WYSIWYG in outgoing drafts', () {
    final doc = Document()..insert(0, 'ordinary text');
    doc.format(0, 8, Attribute.bold);
    doc.format(0, 8, const BackgroundAttribute('#ffffff'));
    final message = serializePlainComposer(doc);
    expect(message.plainText, 'ordinary text');
    expect(message.html, isNull);
  });

  test('selected Matrix mentions survive plain serialization', () {
    final doc = Document()..insert(0, '#general **hello**');
    doc.format(0, 8, const LinkAttribute('https://matrix.to/#/!general:test'));
    final result = serializePlainComposer(doc);
    expect(
      html.parseFragment(result.html!).querySelector('a')!.attributes['href'],
      'https://matrix.to/#/!general:test',
    );
    expect(result.html, contains('<strong>hello</strong>'));
    expect(result.plainText, '#general **hello**');
  });

  for (final value in [
    '*first*\nsecond',
    '*first*\n\nsecond',
    '*first*\n\n\nsecond',
  ]) {
    testWidgets('typed line breaks survive serialization: $value', (
      tester,
    ) async {
      final message = serializeMarkdownEmojiMessage(value, const []);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: MatrixHtmlText(html: message.html!, fallback: value),
        ),
      );
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText(), value.replaceAll('*', ''));
    });
  }

  testWidgets('plain editor keeps markup literal, selection and IME', (
    tester,
  ) async {
    final controller = QuillController.basic();
    final focus = FocusNode();
    final scroll = ScrollController();
    var imagePastes = 0;
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: PlainMessageEditor(
              controller: controller,
              backend: FakeBackend(),
              focusNode: focus,
              scrollController: scroll,
              enabled: true,
              onPasteImage: () async {
                imagePastes++;
                return true;
              },
              onKeyEvent: (_, _) => KeyEventResult.ignored,
              padding: EdgeInsets.zero,
              style: const TextStyle(),
              hintStyle: const TextStyle(),
              placeholder: 'Message',
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '**hello**\n\nnext');
    expect(controller.document.toPlainText(), '**hello**\n\nnext\n');
    expect(controller.document.toDelta().toJson(), [
      {'insert': '**hello**\n\nnext\n'},
    ]);
    expect(find.byType(QuillEditor), findsNothing);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'composing',
        selection: TextSelection.collapsed(offset: 9),
        composing: TextRange(start: 0, end: 9),
      ),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .value
          .composing,
      const TextRange(start: 0, end: 9),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(imagePastes, 1);
    expect(controller.document.toPlainText(), 'composing\n');
    await tester.pumpWidget(const SizedBox());
  });

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

  testWidgets('mobile file attachments expose download without long press', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: MobileAttachmentView(
            backend: FakeBackend(),
            message: ChatMessage(
              id: 'file',
              pending: false,
              sender: 'Test',
              body: '',
              timestamp: DateTime(2026),
              attachment: const ChatAttachment(
                kind: AttachmentKind.file,
                name: 'document.pdf',
                mimeType: 'application/pdf',
                size: 10,
                encrypted: false,
                spoiler: false,
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byTooltip('Download file'), findsOneWidget);
  });

  testWidgets('native login toggles visibility without changing password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: LoginScreen(backend: FakeBackend()),
      ),
    );
    final password = find.widgetWithText(TextFormField, 'Password');
    await tester.enterText(password, 'example-secret');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(of: password, matching: find.byType(TextField)),
    );
    expect(field.obscureText, false);
    expect(field.controller!.text, 'example-secret');
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: password, matching: find.byType(TextField)),
          )
          .obscureText,
      true,
    );
  });

  testWidgets('mobile conversation spacing is stable through reordering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rooms = List.generate(
      4,
      (i) => RoomSummary(
        id: '!r$i:test',
        name: 'Friend $i',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
        isDirect: true,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = rooms;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byKey(ValueKey(rooms.first.id))).height;
    for (var i = 0; i < 6; i++) {
      backend.roomList = backend.roomList.reversed.toList();
      backend.notifyListeners();
      await tester.pumpAndSettle();
      for (final room in rooms) {
        expect(tester.getSize(find.byKey(ValueKey(room.id))).height, height);
      }
    }
  });

  testWidgets('mobile reply highlight meets the timeline edge', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const room = RoomSummary(
      id: '!highlight:test',
      name: 'Highlight room',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: false,
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = [room]
      ..messageList = [
        ChatMessage(
          id: 'ping',
          sender: 'Friend',
          body: 'A reply to you',
          timestamp: DateTime(2026),
          pending: false,
          pingedCurrentUser: true,
        ),
      ];
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight room'));
    await tester.pumpAndSettle();
    final stripe = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border is Border &&
          ((widget.decoration as BoxDecoration).border as Border).left.width ==
              3,
    );
    expect(stripe, findsOneWidget);
    final timeline = find.byKey(const ValueKey('mobile-message-timeline'));
    expect(tester.getTopLeft(stripe).dx, tester.getTopLeft(timeline).dx);
  });
}
