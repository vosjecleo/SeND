import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'desktop stripe does not indent sender, first line or grouped followups',
    (tester) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: 'room',
            name: 'Alignment',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          ),
        ]
        ..messageList = [
          ChatMessage(
            id: 'follow',
            sender: 'Friend',
            senderId: '@friend:test',
            body: 'Followup',
            timestamp: DateTime(2026, 10, 31, 12, 2),
            pending: false,
          ),
          ChatMessage(
            id: 'ping',
            sender: 'Friend',
            senderId: '@friend:test',
            body: 'Highlighted',
            timestamp: DateTime(2026, 10, 31, 12, 1),
            pending: false,
            hasVisualMention: true,
          ),
          ChatMessage(
            id: 'plain',
            sender: 'Other',
            senderId: '@other:test',
            body: 'Plain',
            timestamp: DateTime(2026, 10, 31, 12),
            pending: false,
          ),
        ];
      backend.currentRoom = backend.roomList.single;
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.pumpAndSettle();
      final x = tester
          .getTopLeft(find.byKey(const ValueKey('message-body-plain')))
          .dx;
      for (final id in ['ping', 'follow']) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey('message-body-$id'))).dx,
          closeTo(x, .01),
        );
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('message-sender-ping'))).dx,
        tester
            .getTopLeft(find.byKey(const ValueKey('message-sender-plain')))
            .dx,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
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
            final container = tester.widget<AnimatedContainer>(row);
            expect((container.decoration as BoxDecoration).color!.a > 0, true);
            expect(
              ((container.foregroundDecoration as BoxDecoration).border
                      as Border)
                  .left
                  .width,
              3,
            );
            expect((container.decoration as BoxDecoration).border, isNull);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('mobile reply highlight meets the timeline edge', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const room = RoomSummary(
      id: '!highlight:test',
      name: 'Highlight room',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: false,
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = [room]
      ..messageList = [
        ChatMessage(
          id: 'ping',
          sender: 'Friend',
          body: 'A reply to you',
          timestamp: DateTime(2026),
          pending: false,
          pingedCurrentUser: true,
        ),
      ];
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Highlight room'));
    await tester.pumpAndSettle();
    final stripe = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).border is Border &&
          ((widget.decoration as BoxDecoration).border as Border).left.width ==
              3,
    );
    expect(stripe, findsOneWidget);
    final timeline = find.byKey(const ValueKey('mobile-message-timeline'));
    expect(tester.getTopLeft(stripe).dx, tester.getTopLeft(timeline).dx);
  });
}
