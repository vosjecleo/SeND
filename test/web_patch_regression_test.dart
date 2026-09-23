import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/settings_page_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

void main() {
  testWidgets('backend events reuse app theme but preferences invalidate it', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    final original = tester.widget<MaterialApp>(find.byType(MaterialApp));
    for (var i = 0; i < 25; i++) {
      backend.notifyListeners();
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)),
        same(original),
      );
    }
    await backend.updatePreferences(
      backend.preferences.copyWith(accentColor: 0xff123456),
    );
    await tester.pump();
    final changed = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(changed, isNot(same(original)));
    expect(
      changed.theme!.colorScheme.primary,
      isNot(original.theme!.colorScheme.primary),
    );
    backend.currentStatus = SessionStatus.starting;
    backend.notifyListeners();
    await tester.pump();
    expect(find.text('Sign in'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    backend.dispose();
  });

  testWidgets('login excludes server URL from credential autofill', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].autofillHints, isNull);
    expect(fields[1].autofillHints, contains(AutofillHints.username));
    expect(fields[2].autofillHints, contains(AutofillHints.password));
    expect(fields[1].autocorrect, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    backend.dispose();
  });

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
