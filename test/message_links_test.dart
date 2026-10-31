import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
