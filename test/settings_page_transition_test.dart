import 'package:deltiecord/ui/settings_page_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets(
      'settings pages do not overlap (reduce motion: $reduceMotion)',
      (tester) async {
        Widget page(String text) => MaterialApp(
          home: Scaffold(
            body: SettingsPageTransition(
              reduceMotion: reduceMotion,
              child: Text(text, key: ValueKey(text)),
            ),
          ),
        );
        await tester.pumpWidget(page('Menu'));
        await tester.pumpWidget(page('Settings'));
        if (reduceMotion) {
          await tester.pump();
          expect(find.text('Menu'), findsNothing);
        } else {
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 30));
            final fades = tester.widgetList<FadeTransition>(
              find.descendant(
                of: find.byType(SettingsPageTransition),
                matching: find.byType(FadeTransition),
              ),
            );
            expect(
              fades.where((fade) => fade.opacity.value > 0).length,
              lessThanOrEqualTo(1),
            );
          }
        }
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Menu'), findsNothing);
      },
    );
  }
}
