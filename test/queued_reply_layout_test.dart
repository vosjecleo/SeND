import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'reply keeps its height after sending, mobile=$mobile',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(430, 900)
            : const Size(1440, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const room = RoomSummary(
          id: 'room',
          name: 'Replies',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentRoom = room
          ..roomList = [room];
        ChatMessage message(bool pending) => ChatMessage(
          id: 'reply',
          sender: 'Author',
          senderId: '@me:test',
          body: 'A reply',
          formattedBody: pending
              ? null
              : '<mx-reply><blockquote>Original message</blockquote></mx-reply>A reply',
          timestamp: DateTime(2026, 11, 6),
          own: true,
          pending: pending,
          queued: pending,
          reply: ReplyPreview(
            eventId: 'original',
            sender: 'Friend',
            body: pending ? 'Original message' : 'Original message 🐈 👋',
            senderId: '@friend:test',
          ),
        );
        backend.messageList = [message(true)];
        await tester.pumpWidget(
          DeltiecordApp(
            backend: backend,
            platformOverride: mobile
                ? TargetPlatform.android
                : TargetPlatform.linux,
          ),
        );
        await tester.pumpAndSettle();
        final quote = find.byKey(
          ValueKey(mobile ? 'mobile-reply-reply' : 'reply-preview-reply'),
        );
        final pendingQuote = tester.getSize(quote);
        if (mobile) {
          final connector = tester.getRect(
            find.byKey(const ValueKey('mobile-reply-connector-reply')),
          );
          final avatar = tester.getRect(
            find.byKey(const ValueKey('mobile-message-avatar-reply')),
          );
          expect(connector.bottom + 2, closeTo(avatar.top, 1));
          expect(connector.center.dx, closeTo(avatar.center.dx, .1));
        } else {
          final connector = tester.getRect(
            find.byKey(const ValueKey('reply-connector-reply')),
          );
          final avatar = tester.getRect(
            find.byKey(const ValueKey('message-avatar-reply')),
          );
          expect(avatar.top - (connector.bottom - 3), greaterThan(1));
        }
        final mini = tester.widget<ThemeAvatar>(
          find.byKey(const ValueKey('reply-mini-avatar')),
        );
        expect(mini.autoplay, isFalse);
        expect(mini.radius, 7);
        final pendingContent = tester.getSize(
          find.byKey(
            ValueKey(
              mobile ? 'mobile-message-content-reply' : 'message-content-reply',
            ),
          ),
        );
        backend.messageList = [message(false)];
        backend.notifyListeners();
        await tester.pumpAndSettle();
        expect(tester.getSize(quote), pendingQuote);
        expect(
          tester.getSize(
            find.byKey(
              ValueKey(
                mobile
                    ? 'mobile-message-content-reply'
                    : 'message-content-reply',
              ),
            ),
          ),
          pendingContent,
        );
        await tester.pumpWidget(const SizedBox());
        backend.dispose();
      },
      variant: TargetPlatformVariant.only(
        mobile ? TargetPlatform.android : TargetPlatform.linux,
      ),
    );
  }
}
