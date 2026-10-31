import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

const _room = RoomSummary(
  id: 'room',
  name: 'Positions',
  lastMessage: '',
  unreadCount: 0,
  usesChannelIcon: false,
);

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'reply username shares the sender/body column, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentRoom = _room
          ..roomList = const [_room]
          ..currentPreferences = const AppPreferences(reducedMotion: true)
          ..typingNames = const ['Alice']
          ..messageList = [
            ChatMessage(
              id: 'reply',
              sender: 'Replier',
              senderId: '@peer:test',
              body: 'Reply text',
              timestamp: DateTime(2026),
              pending: false,
              reply: const ReplyPreview(
                eventId: 'old',
                sender: 'Original sender',
                body: 'Original text',
              ),
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        final preview = find.byKey(
          ValueKey(mobile ? 'mobile-reply-reply' : 'reply-preview-reply'),
        );
        final replyText = find.descendant(
          of: preview,
          matching: find.byType(Text),
        );
        final x = tester.getTopLeft(find.text('Replier')).dx;
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('typing-indicator-label')))
              .dx,
          closeTo(x, .01),
        );
        expect(tester.getTopLeft(replyText).dx, closeTo(x, .01));
        expect(
          tester
              .getTopLeft(
                find.byKey(
                  ValueKey(
                    mobile ? 'mobile-message-body-reply' : 'message-body-reply',
                  ),
                ),
              )
              .dx,
          closeTo(x, .01),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final reply in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'desktop short-message avatar uses measured centre, reply=$reply scale=$scale',
        (tester) async {
          final backend = FakeBackend()
            ..currentStatus = SessionStatus.signedIn
            ..currentRoom = _room
            ..roomList = const [_room]
            ..currentPreferences = AppPreferences(fontScale: scale)
            ..messageList = [
              ChatMessage(
                id: 'short',
                sender: 'Sender',
                senderId: '@peer:test',
                body: '*Hi*',
                formattedBody: '<em>Hi</em>',
                timestamp: DateTime(2026),
                pending: false,
                reply: reply
                    ? const ReplyPreview(
                        eventId: 'old',
                        sender: 'Original sender',
                        body: 'Earlier',
                      )
                    : null,
              ),
            ];
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
          final avatar = tester.getRect(
            find.byKey(const ValueKey('message-avatar-short')),
          );
          final sender = tester.getRect(
            find.byKey(const ValueKey('message-sender-short')),
          );
          final body = tester.getRect(
            find.byKey(const ValueKey('message-body-short')),
          );
          expect(avatar.center.dy, closeTo((sender.top + body.bottom) / 2, 1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  for (final scale in [1.0, 1.2]) {
    testWidgets(
      'context menu uses cursor coordinates and actual bounds, scale=$scale',
      (tester) async {
        tester.view.physicalSize = const Size(1300, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentRoom = _room
          ..roomList = const [_room]
          ..currentPreferences = AppPreferences(interfaceScale: scale)
          ..messageList = [
            ChatMessage(
              id: 'long',
              sender: 'Me',
              senderId: '@deltie:example.org',
              body: 'Line\n' * 70,
              timestamp: DateTime(2026),
              pending: false,
              own: true,
            ),
          ];
        await tester.pumpWidget(DeltiecordApp(backend: backend));
        await tester.pumpAndSettle();
        final area = tester.getRect(
          find.byKey(const Key('conversation-timeline-area')),
        );
        final point = area.topLeft + const Offset(100, 70);
        final mouse = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await mouse.addPointer();
        await mouse.down(point);
        await mouse.up();
        await tester.pump();
        final menu = find.byKey(const ValueKey('message-context-menu'));
        expect(menu, findsOneWidget);
        expect(tester.getTopLeft(menu).dx, closeTo(point.dx, 1));
        expect(tester.getTopLeft(menu).dy, closeTo(point.dy, 1));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await mouse.down(area.bottomRight - const Offset(24, 40));
        await mouse.up();
        await tester.pump();
        final rect = tester.getRect(menu);
        expect(rect.right, lessThanOrEqualTo(1300));
        expect(rect.bottom, lessThanOrEqualTo(1000));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
