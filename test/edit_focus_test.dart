import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'editing selects the source row and cancel restores its mention colour, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: 'room',
              name: 'Edit focus',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ]
          ..messageList = [
            ChatMessage(
              id: 'own',
              sender: 'Me',
              body: 'Editable message',
              timestamp: DateTime(2026),
              pending: false,
              own: true,
              hasVisualMention: true,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Edit focus'));
        await tester.pumpAndSettle();
        Color? colour() => mobile
            ? (tester
                          .widget<DecoratedBox>(
                            find.byKey(const ValueKey('message-highlight-own')),
                          )
                          .decoration
                      as BoxDecoration)
                  .color
            : (tester
                          .widget<AnimatedContainer>(
                            find.byKey(const Key('message-row-own')),
                          )
                          .decoration
                      as BoxDecoration)
                  .color;
        final original = colour();
        if (mobile) {
          await tester.longPress(find.text('Editable message'));
        } else {
          await revealMessageActions(tester, find.text('Editable message'));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('message-action-edit')));
        await tester.pumpAndSettle();
        expect(find.text('Editing message'), findsOneWidget);
        expect(colour(), const Color(0xff408cff).withValues(alpha: .17));
        await tester.tap(
          mobile
              ? find.descendant(
                  of: find.byKey(const ValueKey('mobile-composer')),
                  matching: find.byIcon(Icons.close),
                )
              : find.byTooltip('Cancel'),
        );
        await tester.pumpAndSettle();
        expect(colour(), original);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
