import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/measured_avatar_stack.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'first and grouped messages own equal breathing room, mobile=$mobile',
      (tester) async {
        const room = RoomSummary(
          id: 'room',
          name: 'Spacing',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = [room]
          ..messageList = [
            for (final index in [2, 1, 0])
              ChatMessage(
                id: 'entry-$index',
                sender: index == 2 ? 'Other' : 'Peer',
                senderId: index == 2 ? '@other:test' : '@peer:test',
                body: 'Message $index',
                timestamp: DateTime(2026, 11, 3, 12, index),
                pending: false,
                hasVisualMention: true,
              ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(room.name));
        await tester.pumpAndSettle();
        for (final index in [0, 1, 2]) {
          final body = tester.getRect(
            find.byKey(
              ValueKey(
                mobile
                    ? 'mobile-message-body-entry-$index'
                    : 'message-body-entry-$index',
              ),
            ),
          );
          late Rect bounds;
          if (mobile) {
            bounds = tester.getRect(
              find.byKey(ValueKey('message-highlight-entry-$index')),
            );
          } else {
            final row = find.byKey(Key('message-row-entry-$index'));
            bounds = tester.getRect(
              find.descendant(
                of: row,
                matching: find.byType(MeasuredAvatarStack),
              ),
            );
          }
          final top = index == 1
              ? body.top
              : tester.getTopLeft(find.text(index == 2 ? 'Other' : 'Peer')).dy;
          final before = top - bounds.top, after = bounds.bottom - body.bottom;
          final expectedPadding = mobile ? 2.0 : 3.25;
          expect(before, closeTo(expectedPadding, .1));
          expect(after, closeTo(expectedPadding, .1));
          expect(before, closeTo(after, .1));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final rich in [false, true]) {
    testWidgets('explicit newlines have readable leading, rich=$rich', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Scaffold(
            body: DefaultTextStyle(
              style: const TextStyle(fontSize: 14, height: 1.16),
              child: rich
                  ? MatrixHtmlText(
                      html: 'First<br>Second',
                      fallback: 'First\nSecond',
                    )
                  : const MatrixPlainText(
                      text: 'First\nSecond',
                      style: TextStyle(height: 1.28),
                    ),
            ),
          ),
        ),
      );
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final first = editable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final second = editable.getLocalRectForCaret(
        const TextPosition(offset: 6),
      );
      expect(second.top - first.top, greaterThanOrEqualTo(rich ? 19 : 17));
      expect(tester.takeException(), isNull);
    });
  }
}
