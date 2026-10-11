import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('Android attachment-only rows omit empty caption widgets', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!media:test',
          name: 'Media',
          lastMessage: 'photo.jpg',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$attachment-only',
          sender: 'Alice',
          body: '',
          timestamp: DateTime(2026, 9, 3, 12),
          pending: false,
          attachment: const ChatAttachment(
            kind: AttachmentKind.image,
            name: 'photo.jpg',
            mimeType: 'image/jpeg',
            size: 128,
            encrypted: true,
            spoiler: false,
            width: 640,
            height: 480,
          ),
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Media'));
    await tester.pump();

    expect(
      find.byKey(const ValueKey(r'mobile-message-body-$attachment-only')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey(r'mobile-message-attachment-$attachment-only')),
      findsOneWidget,
    );
    final content = find.byKey(
      const ValueKey(r'mobile-message-content-$attachment-only'),
    );
    final editable = find.descendant(
      of: find.byKey(const ValueKey('mobile-composer-field')),
      matching: find.byType(EditableText),
    );
    expect(editable, findsOneWidget);
    expect(
      tester.getTopLeft(editable).dx,
      closeTo(tester.getTopLeft(content).dx, 0.5),
    );
  });

  testWidgets('Android offers Present after leaving the newest viewport', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!mobile-history:test',
          name: 'Mobile history',
          lastMessage: 'latest',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = List.generate(
        60,
        (index) => ChatMessage(
          id: '\$mobile-history-$index',
          sender: 'Alice',
          body: 'Timeline message $index with enough text for a normal row.',
          timestamp: DateTime(2026, 9, 2, 12, index),
          pending: false,
        ),
      );
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Mobile history'));
    await tester.pumpAndSettle();

    expect(find.text('Present'), findsNothing);
    await tester.drag(
      find.byKey(const ValueKey('mobile-message-timeline')),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Present'), findsOneWidget);
  });

  testWidgets('Android exposes older history even before a row is mapped', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..moreHistory = true
      ..roomList = const [
        RoomSummary(
          id: '!empty-page:test',
          name: 'Sparse history',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Sparse history'));
    await tester.pumpAndSettle();

    expect(find.text('Load older messages'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
    final before = backend.historyRequests;
    await tester.tap(find.text('Load older messages'));
    await tester.pump();
    expect(backend.historyRequests, before + 1);
  });

  testWidgets('Android message swipe replies and long press exposes actions', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$event',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'swipe this',
          timestamp: DateTime(2026),
          pending: false,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey(r'swipe-$event')),
      const Offset(-220, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Replying to Alice'), findsOneWidget);

    await tester.longPress(find.byKey(const ValueKey(r'swipe-$event')));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsWidgets);
    expect(find.text('React'), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
    await tester.tap(find.text('Copy text'));
    await tester.pumpAndSettle();
    expect(copiedText, 'swipe this');
  });

  testWidgets('Android timeline groups messages and labels calendar days', (
    tester,
  ) async {
    // Keep both Alice messages on the same calendar day even when the suite
    // happens to cross midnight. The day-boundary behavior is covered by Bob.
    final current = DateTime.now();
    final now = DateTime(current.year, current.month, current.day, 12);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dates:test',
          name: 'Dates',
          lastMessage: 'Today two',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$today-two',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'Today two',
          timestamp: now,
          pending: false,
        ),
        ChatMessage(
          id: r'$today-one',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'Today one',
          timestamp: now.subtract(const Duration(minutes: 1)),
          pending: false,
        ),
        ChatMessage(
          id: r'$yesterday',
          sender: 'Bob',
          senderId: '@bob:test',
          body: 'Yesterday message',
          timestamp: now.subtract(const Duration(days: 1)),
          pending: false,
        ),
      ];

    await pumpMobile(tester, backend);
    await tester.tap(find.text('Dates'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
  });

  testWidgets('Android reply previews jump by event id and truncate', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!reply:test',
          name: 'Replies',
          lastMessage: 'reply',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$reply',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'reply',
          timestamp: DateTime(2026),
          pending: false,
          reply: const ReplyPreview(
            eventId: r'$older',
            sender: 'Bob',
            body: 'A reply body that is deliberately too long for one line',
          ),
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Replies'));
    await tester.pumpAndSettle();

    final preview = find.byKey(const ValueKey(r'mobile-reply-$reply'));
    expect(preview, findsOneWidget);
    final rich = tester.widget<Text>(
      find.descendant(of: preview, matching: find.byType(Text)).first,
    );
    expect(rich.maxLines, 1);
    expect(rich.overflow, TextOverflow.ellipsis);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(backend.jumpedEventIds, contains(r'$older'));
  });

  testWidgets('Android can discard a failed local echo', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!failed:test',
          name: 'Failed send',
          lastMessage: 'stuck',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: 'SeND-45-123',
          sender: 'Deltie',
          senderId: '@deltie:test',
          body: 'stuck',
          timestamp: DateTime(2026),
          pending: false,
          failed: true,
          own: true,
        ),
      ];

    await pumpMobile(tester, backend);
    await tester.tap(find.text('Failed send').first);
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('swipe-SeND-45-123')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard failed send'));
    await tester.pumpAndSettle();

    expect(backend.cancelledMessageIds, ['SeND-45-123']);
  });

  testWidgets('Android drafts survive room navigation', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!a:test',
          name: 'Alice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
        RoomSummary(
          id: '!b:test',
          name: 'Bob',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      'room A draft',
    );
    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('room A draft'), findsOneWidget);
  });

  testWidgets('Android long press on send opens scheduling controls', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!schedule:test',
          name: 'Schedule',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile-composer-field')),
      'Send tomorrow',
    );
    await tester.pump();

    await tester.longPress(find.bySemanticsLabel('Send; hold to send later'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
