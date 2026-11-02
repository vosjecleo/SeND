import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'mobile message groups have unpainted spacing outside highlighted rows',
    (tester) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: 'room',
            name: 'Groups',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          ),
        ]
        ..messageList = [
          ChatMessage(
            id: 'follow',
            sender: 'B',
            senderId: '@b:test',
            body: 'Followup',
            timestamp: DateTime(2026, 1, 1, 12, 2),
            pending: false,
            pingedCurrentUser: true,
          ),
          ChatMessage(
            id: 'first',
            sender: 'B',
            senderId: '@b:test',
            body: 'New group',
            timestamp: DateTime(2026, 1, 1, 12, 1),
            pending: false,
            pingedCurrentUser: true,
          ),
          ChatMessage(
            id: 'old',
            sender: 'A',
            senderId: '@a:test',
            body: 'Older group',
            timestamp: DateTime(2026, 1, 1, 12),
            pending: false,
            pingedCurrentUser: true,
          ),
        ];
      await pumpMobile(tester, backend);
      await tester.tap(find.text('Groups'));
      await tester.pumpAndSettle();
      Rect row(String id) =>
          tester.getRect(find.byKey(ValueKey('message-highlight-$id')));
      expect(row('first').top - row('old').bottom, closeTo(6, .01));
      expect(row('follow').top - row('first').bottom, closeTo(0, .01));
      expect(
        find.byKey(const ValueKey('mobile-group-gap-first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile-group-gap-follow')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
