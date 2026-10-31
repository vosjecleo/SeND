import 'package:flutter/material.dart';
import 'package:deltiecord/ui/emoji_typography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/ui/inline_composer_preview.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:deltiecord/ui/rich_message.dart';

void main() {
  test(
    'composer uses timeline colour emoji typography without changing text or plain fonts',
    () {
      const source = 'Hello 😀 **family 👨‍👩‍👦**';
      const base = TextStyle(fontFamily: 'InterfaceFont', fontSize: 16);
      final span = inlineComposerPreview(source, base);
      expect(span.toPlainText(), source);
      var emojiRuns = 0;
      void visit(TextSpan node, TextStyle inherited) {
        final style = inherited.merge(node.style);
        if (node.text?.isNotEmpty == true) {
          if (colourEmojiPattern.hasMatch(node.text!)) {
            emojiRuns++;
            expect(style.fontFamily, colourEmojiStyle(base).fontFamily);
          } else {
            expect(style.fontFamily, 'InterfaceFont');
          }
        }
        for (final child in node.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) visit(child, style);
        }
      }

      visit(span, base);
      expect(emojiRuns, 2);
    },
  );
  test('double underscore preview is underline, not bold', () {
    final span = inlineComposerPreview('__hi__', const TextStyle());
    final content = span.children!.whereType<TextSpan>().singleWhere(
      (s) => s.text == 'hi',
    );
    expect(content.style!.decoration, TextDecoration.underline);
    expect(content.style!.fontWeight, isNot(FontWeight.bold));
    expect(span.toPlainText(), '__hi__');
  });

  for (final marker in ['*', '**', '_', '__', '~~', '||']) {
    for (final body in [r'hi\', r'\hi', r'h\i']) {
      test('escape cancels $marker formatting in $body', () {
        final input = '$marker$body$marker';
        final sent = serializePlainComposer(Document()..insert(0, input));
        expect(sent.html, '$marker${body.replaceAll('\\', '')}$marker');
        expect(
          inlineComposerPreview(input, const TextStyle()).toPlainText(),
          input,
        );
        final preview = inlineComposerPreview(input, const TextStyle());
        void checkUnformatted(TextSpan span, TextStyle inherited) {
          final effective = inherited.merge(span.style);
          if (span.text?.isNotEmpty == true) {
            expect(effective.fontWeight, isNot(FontWeight.bold));
            expect(effective.fontStyle, isNot(FontStyle.italic));
            expect(effective.decoration, isNull);
            expect(effective.backgroundColor, isNull);
            expect(effective.color, isNull);
          }
          for (final child in span.children ?? const <InlineSpan>[]) {
            if (child is TextSpan) checkUnformatted(child, effective);
          }
        }

        checkUnformatted(preview, const TextStyle());
      });
    }
  }

  test(
    'preview preserves characters, spaces, newlines and muted delimiters',
    () {
      const input = 'a **bold**\n\n ||spoiler||  ';
      final preview = inlineComposerPreview(
        input,
        const TextStyle(color: Colors.white),
      );
      expect(preview.toPlainText(), input);
      final spans = preview.children!.whereType<TextSpan>();
      expect(
        spans.firstWhere((span) => span.text == 'bold').style!.fontWeight,
        FontWeight.bold,
      );
      expect(spans.firstWhere((span) => span.text == '**').style!.color!.a, .5);
    },
  );
}
