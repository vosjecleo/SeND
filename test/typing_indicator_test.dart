import 'package:deltiecord/ui/typing_indicator.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'typing strip is compact without clipping large text, scale=$scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(body: TypingIndicator(names: ['Alice'])),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 150));
        final bounds = tester.getRect(
          find.byKey(const Key('typing-indicator')),
        );
        final label = tester.getRect(find.text('Alice is typing'));
        if (scale == 1) expect(bounds.height, 16);
        expect(label.top, greaterThanOrEqualTo(bounds.top));
        expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
        expect(label.left, bounds.left + 60);
        final dots = [
          for (var index = 0; index < 3; index++)
            find.byKey(ValueKey('typing-dot-$index')),
        ];
        for (final dot in dots) {
          expect(dot, findsOneWidget);
        }
        expect(
          tester.getRect(dots.first).left,
          greaterThanOrEqualTo(bounds.left + 10),
        );
        expect(
          tester.getRect(dots.last).right,
          lessThanOrEqualTo(bounds.left + 50),
        );
        expect(
          tester.getCenter(dots[1]).dx - tester.getCenter(dots.first).dx,
          greaterThan(8),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('typing labels stay concise as participant count grows', () {
    expect(typingLabel(const []), isEmpty);
    expect(typingLabel(const ['Alice']), 'Alice is typing');
    expect(typingLabel(const ['Alice', 'Bob']), 'Alice and Bob are typing');
    expect(
      typingLabel(const ['Alice', 'Bob', 'Carol']),
      'Alice, Bob and Carol are typing',
    );
    expect(
      typingLabel(const ['Alice', 'Bob', 'Carol', 'Dave']),
      'Several people are typing',
    );
  });
}
