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
