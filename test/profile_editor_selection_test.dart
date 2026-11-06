import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/profile_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  testWidgets(
    'scrolling profile settings dismisses selection without losing edits or focus',
    (tester) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeBackend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showProfileEditor(
                  context,
                  backend,
                  const UserProfileSummary(
                    userId: '@person:test',
                    displayName: 'Profile owner',
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final field = find.byType(TextField).first;
      await tester.longPress(field);
      await tester.pumpAndSettle();
      final state = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(state.selectionOverlay?.toolbarIsVisible, isTrue);
      expect(state.selectionOverlay?.handlesAreVisible, isTrue);
      final value = state.widget.controller.value;
      final form = find
          .ancestor(of: field, matching: find.byType(SingleChildScrollView))
          .first;
      await tester.drag(form, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(state.selectionOverlay?.toolbarIsVisible ?? false, isFalse);
      expect(state.selectionOverlay?.handlesAreVisible ?? false, isFalse);
      expect(state.widget.controller.value, value);
      expect(state.widget.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    },
  );
}
