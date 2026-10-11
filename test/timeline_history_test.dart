import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  testWidgets('loads older history from the timeline control', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Older messages exist',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$message',
          sender: 'Alice',
          body: 'Newest message',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();
    final requestsBeforeTap = backend.historyRequests;
    await tester.tap(find.text('Load older messages'));
    await tester.pump();

    expect(backend.historyRequests, requestsBeforeTap + 1);
  });

  testWidgets('history insertion preserves the visible event offset', (
    tester,
  ) async {
    late FakeBackend backend;
    final current = List.generate(
      44,
      (index) => ChatMessage(
        id: '\$current-$index',
        sender: 'Alice',
        body: 'Current message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!anchor:example.org',
          name: 'anchor',
          lastMessage: 'Current message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = current;
    backend.historyLoader = () async {
      backend.messageList = [
        ...current.skip(6),
        ...List.generate(
          14,
          (index) => ChatMessage(
            id: '\$older-$index',
            sender: 'Bob',
            body: 'Older message $index with a variable height\nsecond line',
            timestamp: DateTime(
              2026,
              8,
              16,
              11,
            ).subtract(Duration(minutes: index)),
            pending: false,
          ),
        ),
      ];
      backend.moreHistory = false;
      backend.notifyListeners();
    };

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('anchor'));
    await tester.pump();
    final timelineScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    timelineScrollable.position.jumpTo(
      timelineScrollable.position.maxScrollExtent,
    );
    await tester.pump();
    final anchor = find.text('Current message 35');
    expect(anchor, findsOneWidget);
    // Lazy slivers refine their extent once the variable-height day header
    // is laid out. Reach the actual oldest edge before testing insertion.
    timelineScrollable.position.jumpTo(
      timelineScrollable.position.maxScrollExtent,
    );
    await tester.pump();
    final before = tester.getTopLeft(anchor).dy;

    tester
        .widget<TextButton>(
          find.widgetWithText(TextButton, 'Load older messages'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(anchor).dy, closeTo(before, 1));
    // Appending to one stable reversed list must preserve the row naturally;
    // pagination no longer reconstructs the timeline around a synthetic
    // event anchor.
    expect(backend.lastHistoryAnchor, isNull);
  });

  testWidgets('delayed preview hydration preserves the visible event offset', (
    tester,
  ) async {
    final messages = List.generate(
      48,
      (index) => ChatMessage(
        id: '\$preview-$index',
        sender: 'Alice',
        body: 'Preview message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!preview-anchor:example.org',
          name: 'preview anchor',
          lastMessage: 'Preview message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = messages;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('preview anchor'));
    await tester.pump();
    final timeline = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    timeline.position.jumpTo(timeline.position.maxScrollExtent * 0.72);
    await tester.pump();
    // Anchor an actual selectable timeline message, not the removed DM-list
    // last-message preview (which previously made this assertion vacuous).
    final anchors = find.descendant(
      of: find.byKey(const Key('message-timeline')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is EditableText &&
            widget.controller.text.startsWith('Preview message'),
      ),
    );
    final viewport = tester.getRect(find.byKey(const Key('message-timeline')));
    final visibleElement = anchors.evaluate().firstWhere((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return rect.top >= viewport.top + 30 &&
          rect.bottom <= viewport.bottom - 30;
    });
    final anchor = find.byWidget(visibleElement.widget);
    final anchorText = tester.widget<EditableText>(anchor).controller.text;
    final before = tester.getTopLeft(find.text(anchorText)).dy;

    backend.messageList = [
      for (final message in messages)
        if (message.id == r'$preview-20')
          ChatMessage(
            id: message.id,
            sender: message.sender,
            body: message.body,
            timestamp: message.timestamp,
            pending: false,
            linkPreview: LinkPreview(
              url: Uri.parse('https://example.org/article'),
              title: 'Hydrated preview title',
              description: 'Metadata arrived after the text timeline.',
              siteName: 'example.org',
              width: 640,
              height: 360,
            ),
          )
        else
          message,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(tester.getTopLeft(find.text(anchorText)).dy, closeTo(before, 1));
  });

  testWidgets('live messages keep a present timeline pinned to the bottom', (
    tester,
  ) async {
    final initialMessages = List.generate(
      30,
      (index) => ChatMessage(
        id: '\$live-$index',
        sender: index.isEven ? 'Alice' : 'Bob',
        body: 'Live message $index',
        timestamp: DateTime(2026, 8, 16, 12).subtract(Duration(minutes: index)),
        pending: false,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!live:example.org',
          name: 'live',
          lastMessage: 'Live message 0',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = initialMessages;

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('live'));
    await tester.pumpAndSettle();
    final timeline = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('message-timeline')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(timeline.position.pixels, 0);

    backend.messageList = [
      ChatMessage(
        id: r'$live-new',
        sender: 'Alice',
        body: 'A new live message',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();

    expect(timeline.position.pixels, 0);
    expect(find.text('A new live message'), findsOneWidget);

    // Homeserver acknowledgement may replace a local echo with a different
    // event ID while retaining the same visible message.
    backend.messageList = [
      ChatMessage(
        id: r'$live-accepted',
        sender: 'Alice',
        body: 'A new live message',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(timeline.position.pixels, 0);

    // Progressive reply/preview hydration can change a live row's height on a
    // later backend notification without introducing another event.
    backend.messageList = [
      ChatMessage(
        id: r'$live-accepted',
        sender: 'Alice',
        body: 'A new live message\nwith hydrated metadata',
        timestamp: DateTime(2026, 8, 16, 12, 1),
        pending: false,
      ),
      ...initialMessages,
    ];
    backend.notifyListeners();
    await tester.pump();
    await tester.pump();
    expect(timeline.position.pixels, 0);
  });

  testWidgets('historical timelines expose a load newer control', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreFuture = true
      ..roomList = const [
        RoomSummary(
          id: '!history:example.org',
          name: 'history',
          lastMessage: 'Historical message',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$historical',
          sender: 'Alice',
          body: 'Historical message',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('history'));
    await tester.pump();

    expect(find.text('Load newer messages'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('load-newer-messages')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('load-newer-messages')));
    await tester.pump();
    expect(backend.futureRequests, 1);
    expect(backend.lastFutureAnchor, isNull);
  });

  testWidgets('offers jump to present after scrolling away from recent chat', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!history:example.org',
          name: 'history',
          lastMessage: 'latest',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = List.generate(
        40,
        (index) => ChatMessage(
          id: '\$history-$index',
          sender: index.isEven ? 'Alice' : 'Bob',
          senderId: index.isEven ? '@alice:example.org' : '@bob:example.org',
          body: 'Timeline message $index with enough content to fill a row.',
          timestamp: DateTime(2026, 8, 15, 0, index),
          pending: false,
        ),
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('history'));
    await tester.pumpAndSettle();

    expect(find.text('Jump to present'), findsNothing);
    await tester.drag(
      find.byKey(const Key('message-timeline')),
      const Offset(0, 600),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jump to present'), findsOneWidget);
    await tester.tap(find.text('Jump to present'));
    await tester.pumpAndSettle();
    expect(backend.jumpPresentRequests, 1);
    expect(find.text('Jump to present'), findsNothing);
  });
}
