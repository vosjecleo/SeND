import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/archive_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final panel in ['navigation', 'details']) {
    testWidgets('opening $panel releases the hidden composer keyboard', (
      tester,
    ) async {
      const room = RoomSummary(
        id: '!room:test',
        name: 'Alice',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
        isDirect: true,
      );
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = [room];
      await pumpMobile(tester, backend);
      await tester.tap(find.text('Alice').hitTestable().first);
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('mobile-composer-field'));
      await tester.enterText(field, 'Keep my draft');
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.widget.focusNode.hasFocus, isTrue);
      await tester.tap(find.byKey(ValueKey('mobile-open-$panel')));
      await tester.pumpAndSettle();
      expect(editable.widget.focusNode.hasFocus, isFalse);
      expect(editable.widget.focusNode.canRequestFocus, isFalse);
      expect(editable.widget.controller.text, 'Keep my draft');
      expect(tester.testTextInput.isVisible, isFalse);
      // A delayed resume/language callback must not reopen an off-screen editor.
      editable.requestKeyboard();
      await tester.pumpAndSettle();
      expect(editable.widget.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      if (panel == 'navigation') {
        final search = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Search direct messages',
        );
        await tester.tap(search);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
        expect(editable.widget.focusNode.hasFocus, isFalse);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        final rooms = find.descendant(
          of: find.byType(ArchivePullList),
          matching: find.byType(ListView),
        );
        expect(tester.getBottomRight(rooms).dy, lessThanOrEqualTo(600));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    });
  }
}
