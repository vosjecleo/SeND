import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets(
    'last mobile member can scroll above the system navigation area',
    (tester) async {
      tester.view.viewPadding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetViewPadding);
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = const [
          RoomSummary(
            id: 'channel',
            name: 'Members test',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: true,
          ),
        ]
        ..memberList = List.generate(
          30,
          (i) =>
              RoomMemberSummary(userId: '@m$i:test', displayName: 'Member $i'),
        );
      await pumpMobile(tester, backend);
      await tester.tap(find.text('Members test'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mobile-open-details')));
      await tester.pumpAndSettle();
      final list = find.descendant(
        of: find.byKey(const ValueKey('mobile-details-panel')),
        matching: find.byType(ListView),
      );
      await tester.dragUntilVisible(
        find.text('Member 29'),
        list,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Member 29')).dy,
        lessThanOrEqualTo(900 - 48 - 16),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
