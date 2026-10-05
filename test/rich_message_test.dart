import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/ui/rich_message.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pretty-printed HTML does not add a source-whitespace row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MatrixHtmlText(
              html: '<p><em>italic\n</em></p>\n<p>next</p>\n',
              fallback: 'italic\nnext',
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText().split('\n').length, 2);
  });
  for (final markup in ['*italic*', '**bold**', '*italic*\nnext']) {
    testWidgets('desktop markdown has no extra row: $markup', (tester) async {
      final document = Document()..insert(0, markup);
      final message = serializePlainComposer(document);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MatrixHtmlText(
                html: message.html!,
                fallback: message.plainText,
              ),
            ),
          ),
        ),
      );
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(text.textSpan!.toPlainText().endsWith('\n'), isFalse);
      expect(
        tester.getSize(find.byType(SelectableText)).height,
        lessThan(markup.contains('\n') ? 55 : 30),
      );
    });
  }
  test('fresh composer drops pasted background and pending formatting', () {
    final controller = QuillController.basic();
    addTearDown(controller.dispose);
    controller.document.insert(0, 'caption');
    controller.document.format(0, 7, const BackgroundAttribute('#ffffff'));
    controller.toggledStyle = Style.fromJson({
      'background': '#ffffff',
      'bold': true,
    });
    resetRichComposer(controller);
    expect(controller.document.toPlainText(), '\n');
    expect(controller.toggledStyle.isEmpty, isTrue);
    expect(controller.document.toDelta().toJson(), [
      {'insert': '\n'},
    ]);
    controller.document.insert(0, 'next');
    expect(controller.document.toDelta().toJson(), [
      {'insert': 'next\n'},
    ]);
  });
  test('plain range edits do not preserve legacy rich formatting', () {
    final document = plainMessageDocument(
      'bold plain',
      '<strong>bold</strong> plain',
    );
    reconcileRichMessageDocument(document, 'bold plain', 'bold changed');
    final message = serializePlainComposer(document);
    expect(message.plainText, 'bold changed');
    expect(message.html, isNull);
    expect(message.plainText, 'bold changed');
  });
  test('selected custom emoji does not disable typed Markdown', () {
    final emoji = CustomEmojiReference(
      id: Uri.parse('mxc://test/emoji'),
      name: 'wave',
    );
    final document = Document()..insert(0, '**bold** :wave:');
    document.format(9, 6, LinkAttribute(customEmojiEditorLink(emoji)));
    final message = serializePlainComposer(document);
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('data-mx-emoticon'));
    expect(message.html, contains('mxc://test/emoji'));
  });
  test(
    'recognizes standalone Unicode emoji without treating text as emoji',
    () {
      expect(isUnicodeEmojiOnly('😁 🐈'), isTrue);
      expect(isUnicodeEmojiOnly('👩🏽‍💻'), isTrue);
      expect(isUnicodeEmojiOnly('1️⃣'), isTrue);
      expect(isUnicodeEmojiOnly('hug! 🐈'), isFalse);
      expect(isUnicodeEmojiOnly('123'), isFalse);
    },
  );

  testWidgets('standalone Unicode emoji use jumbo message sizing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MatrixPlainText(text: '🐈', selectable: false)),
      ),
    );

    final text = tester.widget<Text>(find.byType(Text));
    expect(text.textSpan?.style?.fontSize, 64);
  });

  test('converts typed markup without exposing formatting controls', () {
    final document = Document()..insert(0, '**bold** _italic_ ||hidden||');

    final message = serializePlainComposer(document);

    expect(message.plainText, '**bold** _italic_ ||hidden||');
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('<em>italic</em>'));
    expect(message.html, contains('data-mx-spoiler'));
  });

  test('keeps filesystem paths as literal plain text', () {
    final document = Document()
      ..insert(0, 'sudo apt install /path/to/deltiecord_0.3.6_amd64.deb');

    final message = serializePlainComposer(document);

    expect(
      message.plainText,
      'sudo apt install /path/to/deltiecord_0.3.6_amd64.deb',
    );
    expect(message.html, isNull);
  });

  test('serializes linked composer emoji as Matrix inline media', () {
    final emoji = CustomEmojiReference(
      id: Uri(scheme: 'mxc', host: 'example.org', path: '/stable'),
      name: 'wave',
    );
    final document = Document()..insert(0, ':wave:');
    document.format(0, 6, LinkAttribute(customEmojiEditorLink(emoji)));

    final message = serializePlainComposer(document);

    expect(message.plainText, ':wave:');
    expect(message.html, contains('data-mx-emoticon'));
    expect(message.html, contains('mxc://example.org/stable'));
    expect(message.html, isNot(contains('emoji.deltiecord.invalid')));
  });

  testWidgets('spoiler paragraph receipts stay on the content row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MatrixHtmlText(
              html: '<p><span data-mx-spoiler="">secret</span></p>\n',
              fallback: 'secret',
              trailing: TextSpan(text: ' ✓'),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), 'secret ✓');
    expect(tester.getSize(find.byType(SelectableText)).height, lessThan(30));
  });

  testWidgets('rich paragraphs do not retain an empty trailing row', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MatrixHtmlText(
              html: '<p>sudo apt install /path/to/file_name.deb</p>',
              fallback: 'sudo apt install /path/to/file_name.deb',
            ),
          ),
        ),
      ),
    );

    final height = tester.getSize(find.byType(SelectableText)).height;
    expect(height, lessThan(30));
  });
}
