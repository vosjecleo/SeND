import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/ui/message_metadata.dart';

void main() {
  testWidgets('short and long day labels stay centred with equal edge lines', (
    tester,
  ) async {
    for (final date in [DateTime.now(), DateTime(2026, 1, 1)]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(width: 600, child: MessageDaySeparator(date: date)),
          ),
        ),
      );
      final label = find.descendant(
        of: find.byType(MessageDaySeparator),
        matching: find.byType(Text),
      );
      final dividers = find.byType(Divider);
      expect(
        tester.getCenter(label).dx,
        closeTo(tester.getCenter(find.byType(MessageDaySeparator)).dx, .01),
      );
      expect(
        tester.getSize(dividers.first).width,
        closeTo(tester.getSize(dividers.last).width, .01),
      );
      final bounds = tester.getRect(find.byType(MessageDaySeparator));
      final leftInset = tester.getTopLeft(dividers.first).dx - bounds.left;
      final rightInset = bounds.right - tester.getTopRight(dividers.last).dx;
      expect(leftInset, greaterThanOrEqualTo(0));
      expect(leftInset, lessThanOrEqualTo(bounds.width * .04));
      expect(rightInset, closeTo(leftInset, .01));
    }
  });

  testWidgets('day separators fit narrow layouts at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Center(
            child: SizedBox(
              width: 180,
              child: MessageDaySeparator(date: DateTime(2026, 8, 16)),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
