import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
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
    // Picking a suggestion stores a Matrix link attribute, not plain text.
    // It must get the same preview as a manually typed mention.
    controller.document = Document()..insert(0, '@friend:test');
    controller.formatText(
      0,
      12,
      LinkAttribute('https://matrix.to/#/@friend:test'),
    );
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    final preview = field.controller!.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      style: const TextStyle(),
      withComposing: false,
    );
    final highlighted = <TextSpan>[];
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        if (span.style?.backgroundColor == const Color(0x403fa9f5)) {
          highlighted.add(span);
        }
        for (final child in span.children ?? <InlineSpan>[]) {
          walk(child);
        }
      }
    }

    walk(preview);
    expect(highlighted.single.text, '@friend:test');
    expect(preview.toPlainText(), '@friend:test');
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
}
