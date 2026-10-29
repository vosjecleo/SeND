import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/update_notes_store.dart';
import 'package:deltiecord/ui/update_notes_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'fresh installs suppress notes, compiled upgrades show once, downgrades do not',
    () async {
      final store = UpdateNotesStore();
      expect(await store.shouldShow(133, existingInstall: false), false);
      expect(await store.shouldShow(134, existingInstall: true), true);
      await store.acknowledge(134);
      expect(await store.shouldShow(134, existingInstall: true), false);
      expect(await store.shouldShow(133, existingInstall: true), false);
      await store.acknowledge(133);
      expect(await store.shouldShow(134, existingInstall: true), false);
    },
  );
  test(
    'existing installs migrate without needing a prior notes marker',
    () async {
      expect(
        await UpdateNotesStore().shouldShow(134, existingInstall: true),
        true,
      );
    },
  );
  testWidgets('notes are scrollable and Okay acknowledges the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showUpdateNotes(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('An Update?!? Whats changed...?'), findsOneWidget);
    expect(find.text('Full log'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.tap(find.text('Okay!'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
