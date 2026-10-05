import 'package:deltiecord/ui/rich_message.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only lightweight inline formatting is emitted', () {
    final message = serializeMarkdownEmojiMessage(
      '*italic* **bold** _italic too_ __underlined__ ~~struck~~ ||secret||',
      const [],
    );
    for (final tag in ['em', 'strong', 'u', 'del']) {
      expect(message.html, contains('<$tag>'));
    }
    expect(message.html, contains('<span data-mx-spoiler>secret</span>'));
    expect(message.html, isNot(contains('<p>')));
    expect(message.html, isNot(endsWith('\n')));
  });

  for (final literal in [
    '>hello',
    '# heading',
    '- item',
    '1. item',
    '```\ncode\n```',
    '[link](https://example.org)',
    '<b>not HTML</b>',
  ]) {
    testWidgets(
      'block syntax stays literal beside inline formatting: $literal',
      (tester) async {
        final source = '$literal\n\n*italic*\nnext';
        final message = serializeMarkdownEmojiMessage(source, const []);
        expect(message.html, isNot(contains('<blockquote>')));
        expect(message.html, isNot(contains('<p>')));
        expect(message.html, isNot(contains('<pre>')));
        expect(message.html, isNot(contains('<ul>')));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatrixHtmlText(
                html: message.html!,
                fallback: message.plainText,
              ),
            ),
          ),
        );
        final text = tester.widget<SelectableText>(find.byType(SelectableText));
        expect(text.textSpan!.toPlainText(), '$literal\n\nitalic\nnext');
      },
    );
  }
}
