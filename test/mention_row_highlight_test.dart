import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    for (final body in ['@everyone!', 'Hi @me:test']) {
      testWidgets(
        'a ping highlights its whole message, mobile=$mobile, body=$body',
        (tester) async {
          final backend = FakeBackend()
            ..currentStatus = SessionStatus.signedIn
            ..roomList = const [
              RoomSummary(
                id: '!r:test',
                name: 'Mention test',
                lastMessage: '',
                unreadCount: 1,
                usesChannelIcon: false,
              ),
            ]
            ..messageList = [
              ChatMessage(
                id: 'ping',
                sender: 'Me',
                senderId: '@me:test',
                body: body,
                timestamp: DateTime(2026, 10, 26, 12),
                pending: false,
                own: true,
                hasVisualMention: true,
              ),
            ];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            await tester.pumpWidget(DeltiecordApp(backend: backend));
          }
          await tester.tap(find.text('Mention test'));
          await tester.pumpAndSettle();
          final row = find.byKey(
            mobile
                ? const ValueKey('swipe-ping')
                : const Key('message-row-ping'),
          );
          expect(row, findsOneWidget);
          bool pingDecoration(Decoration? decoration) =>
              decoration is BoxDecoration &&
              decoration.border is Border &&
              (decoration.border as Border).left.width == 3 &&
              (decoration.color?.a ?? 0) > 0;
          if (mobile) {
            final decor = find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (w) => w is DecoratedBox && pingDecoration(w.decoration),
              ),
            );
            expect(decor, findsWidgets);
          } else {
            expect(
              pingDecoration(tester.widget<AnimatedContainer>(row).decoration),
              true,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
