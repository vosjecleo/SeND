import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  @override
  Future<void> jumpToPresent() async {
    jumpPresentRequests++;
    moreFuture = false;
    final retained = List<ChatMessage>.of(messageList);
    ChatMessage head(String body) => ChatMessage(
      id: 'newest',
      sender: 'Friend',
      body: body,
      timestamp: DateTime(2026, 11, 2),
      pending: false,
    );
    messageList = [head('Newest message'), ...retained];
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    messageList = [
      head('Newest message\nwith late layout\nthird line'),
      ...retained,
    ];
    notifyListeners();
  }
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'Present reaches the exact bottom after retained history and late layout, mobile=$mobile',
      (tester) async {
        final backend = _Backend()
          ..currentStatus = SessionStatus.signedIn
          ..moreFuture = true
          ..roomList = const [
            RoomSummary(
              id: 'room',
              name: 'Present test',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ]
          ..messageList = List.generate(
            80,
            (i) => ChatMessage(
              id: 'old-$i',
              sender: 'Friend',
              body: 'Retained message $i',
              timestamp: DateTime(2026, 11, 1).subtract(Duration(minutes: i)),
              pending: false,
            ),
          );
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Present test'));
        await tester.pumpAndSettle();
        final list = find.byKey(
          mobile
              ? const ValueKey('mobile-message-timeline')
              : const Key('message-timeline'),
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        scroll.position.jumpTo(1500);
        await tester.pumpAndSettle();
        expect(find.text('Load messages across gap'), findsNothing);
        expect(find.byKey(const ValueKey('mobile-load-gap')), findsNothing);
        expect(find.byKey(const Key('load-newer-messages')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('jump-to-present')));
        await tester.pumpAndSettle();
        expect(backend.jumpPresentRequests, 1);
        expect(
          scroll.position.pixels,
          closeTo(scroll.position.minScrollExtent, .01),
        );
        expect(
          find
              .text('Newest message\nwith late layout\nthird line')
              .hitTestable(),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          scroll.position.pixels,
          closeTo(scroll.position.minScrollExtent, .01),
        );
        expect(backend.messageList.length, 81);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
