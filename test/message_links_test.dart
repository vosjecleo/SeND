import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final dark in [false, true]) {
    for (final rich in [false, true]) {
      testWidgets(
        'URLs use the same link colour in both renderers, dark=$dark rich=$rich',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              home: Scaffold(
                body: rich
                    ? const MatrixHtmlText(
                        html: '<strong>https://example.org</strong>',
                        fallback: 'https://example.org',
                      )
                    : const MatrixPlainText(text: 'https://example.org'),
              ),
            ),
          );
          final span = tester
              .widget<SelectableText>(find.byType(SelectableText))
              .textSpan!;
          final links = <TextSpan>[];
          void walk(InlineSpan span) {
            if (span is TextSpan) {
              if (span.text == 'https://example.org' &&
                  span.recognizer != null) {
                links.add(span);
              }
              for (final child in span.children ?? <InlineSpan>[]) {
                walk(child);
              }
            }
          }

          walk(span);
          expect(links, hasLength(1));
          expect(
            links.single.style!.color,
            dark ? const Color(0xff00a8fc) : const Color(0xff0068e0),
          );
          expect(links.single.style!.decoration, TextDecoration.underline);
        },
      );
    }
  }
  for (final html in [
    '<mx-reply><blockquote>old message</blockquote></mx-reply>See https://example.org/video.',
    '<strong>See https://example.org/video.</strong>',
    '<a href="https://example.org/video">https://example.org/video</a>',
  ]) {
    testWidgets(
      'rich message URLs stay blue, underlined and clickable: $html',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MatrixHtmlText(
                html: html,
                fallback: 'See https://example.org/video.',
              ),
            ),
          ),
        );
        final root = tester
            .widget<SelectableText>(find.byType(SelectableText))
            .textSpan!;
        final links = <TextSpan>[];
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            if (span.text != null &&
                span.recognizer != null &&
                span.style?.decoration == TextDecoration.underline) {
              links.add(span);
            }
            for (final child in span.children ?? <InlineSpan>[]) {
              walk(child);
            }
          }
        }

        walk(root);
        expect(links, hasLength(1));
        expect(links.single.style!.color, const Color(0xff0068e0));
        (links.single.recognizer as TapGestureRecognizer).onTap!();
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('https://example.org/video'),
          ),
          findsOneWidget,
        );
        expect(find.text('Open link'), findsOneWidget);
      },
    );
  }
  testWidgets('code URLs are literal, not auto-linked', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MatrixHtmlText(
            html: '<code>https://example.org</code>',
            fallback: 'https://example.org',
          ),
        ),
      ),
    );
    final root = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .textSpan!;
    void check(InlineSpan span) {
      if (span is TextSpan) {
        expect(span.recognizer, isNull);
        for (final child in span.children ?? <InlineSpan>[]) {
          check(child);
        }
      }
    }

    check(root);
  });
  testWidgets('formatted link reveals destination before launching', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MatrixHtmlText(
            html: '<a href="https://example.org/actual">Friendly label</a>',
            fallback: 'Friendly label',
            selectable: false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Friendly label'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.org/actual'), findsOneWidget);
    expect(find.text('Open link'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  TestWidgetsFlutterBinding.ensureInitialized();
}
