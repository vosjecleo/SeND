import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('renders replies as metadata above the message body', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Reply',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$reply',
          sender: 'Alice',
          body: 'My actual reply',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$reply',
            sender: 'Bob',
            body: 'Original message',
          ),
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(find.textContaining('Original message'), findsOneWidget);
    expect(find.text('My actual reply'), findsOneWidget);
    expect(find.textContaining('> <'), findsNothing);

    await revealMessageActions(tester, find.text('My actual reply'));
    tester
        .widget<IconButton>(find.byKey(const Key('message-action-reply')))
        .onPressed!();
    await tester.pump();
    expect(find.text('Replying to Alice'), findsOneWidget);
    await enterComposer(tester, 'A second reply');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastReplyToMessageId, r'$reply');
  });

  testWidgets('repeated reply jumps retain their event targets and blink', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!replies:example.org',
          name: 'replies',
          lastMessage: 'second response',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$response-two',
          sender: 'Bob',
          body: 'second response',
          timestamp: DateTime(2026, 8, 16, 12, 3),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$target-two',
            sender: 'Alice',
            body: 'second target body',
          ),
        ),
        ChatMessage(
          id: r'$target-two',
          sender: 'Alice',
          body: 'second target body',
          timestamp: DateTime(2026, 8, 16, 12, 2),
          pending: false,
        ),
        ChatMessage(
          id: r'$response-one',
          sender: 'Bob',
          body: 'first response',
          timestamp: DateTime(2026, 8, 16, 12, 1),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$target-one',
            sender: 'Alice',
            body: 'first target body',
          ),
        ),
        ChatMessage(
          id: r'$target-one',
          sender: 'Alice',
          body: 'first target body',
          timestamp: DateTime(2026, 8, 16, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('replies'));
    await tester.pump();

    await tester.tap(find.byKey(const Key(r'reply-preview-$response-one')));
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    var highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const Key(r'message-row-$target-one')),
    );
    expect((highlighted.decoration as BoxDecoration).color, isNotNull);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key(r'reply-preview-$response-two')));
    await tester.pump(const Duration(milliseconds: 170));
    await tester.pump();
    highlighted = tester.widget<AnimatedContainer>(
      find.byKey(const Key(r'message-row-$target-two')),
    );
    expect((highlighted.decoration as BoxDecoration).color, isNotNull);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
