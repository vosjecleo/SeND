import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  testWidgets('native login toggles visibility without changing password', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: LoginScreen(backend: FakeBackend()),
      ),
    );
    final password = find.widgetWithText(TextFormField, 'Password');
    await tester.enterText(password, 'example-secret');
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.descendant(of: password, matching: find.byType(TextField)),
    );
    expect(field.obscureText, false);
    expect(field.controller!.text, 'example-secret');
    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.descendant(of: password, matching: find.byType(TextField)),
          )
          .obscureText,
      true,
    );
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
}
