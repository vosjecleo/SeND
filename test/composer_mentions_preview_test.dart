import 'package:deltiecord/ui/inline_composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final token in ['@everyone', '@all', '@room', '@friend:example.org']) {
    test('composer paints $token without changing draft offsets', () {
      final text = 'Hi **$token** 🙂';
      final span = inlineComposerPreview(text, const TextStyle(fontSize: 16));
      expect(span.toPlainText(), text);
      final mentions = <TextSpan>[];
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.style?.backgroundColor == const Color(0x403fa9f5)) {
            mentions.add(span);
          }
          for (final child in span.children ?? <InlineSpan>[]) {
            walk(child);
          }
        }
      }

      walk(span);
      expect(mentions.single.text, token);
      expect(mentions.single.style!.color, const Color(0xff408cff));
      expect(mentions.single.style!.fontWeight, FontWeight.bold);
    });
  }
  test('escaped tokens, URLs and longer names are not composer pings', () {
    final span = inlineComposerPreview(
      r'\@everyone @alligator https://example.org/@all',
      null,
    );
    void check(InlineSpan span) {
      if (span is TextSpan) {
        expect(span.style?.backgroundColor, isNull);
        for (final child in span.children ?? <InlineSpan>[]) {
          check(child);
        }
      }
    }

    check(span);
  });
}
