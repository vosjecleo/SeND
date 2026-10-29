import 'package:deltiecord/ui/plain_message_editor.dart';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/matrix_html_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('renders interoperable polls without leaking hidden results', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!polls:example.org',
          name: 'polls',
          lastMessage: 'Pick one',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$poll',
          sender: 'Alice',
          body: 'Pick one',
          timestamp: DateTime(2026, 9, 2, 12),
          pending: false,
          poll: const PollSummary(
            question: 'Pick one',
            maxSelections: 1,
            ended: false,
            disclosed: false,
            answers: [
              PollAnswerSummary(id: 'a', text: 'Cats', votes: 4),
              PollAnswerSummary(id: 'b', text: 'Dogs', votes: 2),
            ],
          ),
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('polls'));
    await tester.pumpAndSettle();

    expect(find.text('Pick one'), findsWidgets);
    expect(find.text('Cats'), findsOneWidget);
    expect(find.text('Dogs'), findsOneWidget);
    expect(find.text('Results hidden'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNWidgets(2));
  });

  testWidgets('edits, deletes, and reacts through message actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Original',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$own',
          sender: 'Deltie',
          body: 'Original',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
          own: true,
          canRedact: true,
          reactions: const [
            ReactionSummary(key: '👍', count: 2, reactedByMe: true),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    await tester.tap(find.text('👍 2'));
    expect(backend.toggledReactions, [(r'$own', '👍')]);

    final hoverOnly = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hoverOnly.addPointer();
    await hoverOnly.moveTo(
      tester.getCenter(find.byKey(const ValueKey(r'message-body-$own'))),
    );
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Reply'), findsNothing);
    await hoverOnly.removePointer();

    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Reply'), findsNothing);

    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    expect(find.text('Reply'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Reply'), findsNothing);

    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    await tester.tap(find.byKey(const Key('message-action-react')));
    await tester.pumpAndSettle();
    expect(find.text('Emoji'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'tada');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emoji-picker-result-🎉')));
    await tester.pumpAndSettle();
    expect(backend.toggledReactions, [(r'$own', '👍'), (r'$own', '🎉')]);

    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    await tester.tap(find.byKey(const Key('message-action-edit')));
    await tester.pump();
    expect(find.text('Editing message'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(find.text('Editing message'), findsNothing);
    expect(
      tester
          .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
          .controller
          .document
          .toPlainText()
          .trim(),
      isEmpty,
    );
    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    await tester.tap(find.byKey(const Key('message-action-edit')));
    await tester.pump();
    await enterComposer(tester, 'Changed');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(backend.lastEditMessageId, r'$own');

    await revealMessageActions(
      tester,
      find.byKey(const ValueKey(r'message-body-$own')),
    );
    await tester.tap(find.byKey(const Key('message-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(backend.redactedMessageIds, [r'$own']);
  });

  testWidgets('renders Matrix rich text and revealable spoilers', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello secret',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$rich',
          sender: 'Alice',
          body: 'Hello secret',
          formattedBody:
              '<strong>Hello</strong> <span data-mx-spoiler>secret</span>',
          timestamp: DateTime(2026, 8, 13, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('general'));
    await tester.pump();

    final richMessage = find.byType(MatrixHtmlText);
    final selectable = tester.widget<SelectableText>(
      find.descendant(of: richMessage, matching: find.byType(SelectableText)),
    );
    TextSpan? concealed;
    selectable.textSpan!.visitChildren((span) {
      if (span is TextSpan && span.text == 'secret') concealed = span;
      return true;
    });
    expect(concealed, isNotNull);
    expect(concealed!.style!.color, concealed!.style!.backgroundColor);
    expect(concealed!.recognizer, isA<TapGestureRecognizer>());
    (concealed!.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(
      find.descendant(
        of: richMessage,
        matching: find.textContaining('Hello secret'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows homeserver accepted and participant read states', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$newer-read',
          sender: 'Deltie',
          senderId: '@deltie:example.org',
          body: 'second message in the cluster',
          timestamp: DateTime(2026, 8, 15, 0, 1),
          pending: false,
          own: true,
          readBy: const [
            ReceiptReaderSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
        ChatMessage(
          id: r'$read',
          sender: 'Deltie',
          senderId: '@deltie:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 15),
          pending: false,
          own: true,
          readBy: const [
            ReceiptReaderSummary(
              userId: '@alice:example.org',
              displayName: 'Alice',
            ),
          ],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byTooltip('Read by Alice'), findsOneWidget);
  });

  testWidgets('chat timestamps default to 24-hour time and allow AM/PM', (
    tester,
  ) async {
    final today = DateTime.now();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!time:example.org',
          name: 'time',
          lastMessage: 'clock',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$time',
          sender: 'Alice',
          body: 'clock',
          timestamp: DateTime(today.year, today.month, today.day, 13, 5),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('time'));
    await tester.pump();

    expect(find.text('13:05'), findsOneWidget);
    backend.currentPreferences = backend.preferences.copyWith(
      use24HourTime: false,
    );
    backend.notifyListeners();
    await tester.pump();
    expect(find.text('1:05 PM'), findsOneWidget);
  });

  testWidgets('desktop avatars center on the first message entry', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!avatar-layout:example.org',
          name: 'avatar layout',
          lastMessage: 'Aligned content',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$avatar-layout',
          sender: 'Alice',
          body: 'Aligned content',
          timestamp: DateTime(2026, 9, 3, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('avatar layout'));
    await tester.pumpAndSettle();

    final avatarRect = tester.getRect(
      find.byKey(const ValueKey(r'message-avatar-$avatar-layout')),
    );
    final senderRect = tester.getRect(
      find.byKey(const ValueKey(r'message-sender-$avatar-layout')),
    );
    final bodyRect = tester.getRect(
      find.byKey(const ValueKey(r'message-body-$avatar-layout')),
    );
    expect(
      avatarRect.center.dy,
      closeTo((senderRect.top + bodyRect.bottom) / 2, 1.5),
    );
  });
}
