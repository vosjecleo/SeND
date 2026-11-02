import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  bool writable = false;
  @override
  bool canSendMessagesToRoom(String roomId) => writable;
  void allowPosting() {
    writable = true;
    notifyListeners();
  }
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'read-only channel hides input and follows permission changes, mobile=$mobile',
      (tester) async {
        final backend = _Backend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: '!announcements:test',
              name: 'Announcements',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: true,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Announcements'));
        await tester.pumpAndSettle();
        expect(
          find.text('You cannot send messages in this channel.'),
          findsOneWidget,
        );
        expect(find.byType(PlainMessageEditor), findsNothing);
        expect(find.byTooltip('Send'), findsNothing);
        expect(find.byKey(const ValueKey('mobile-composer')), findsNothing);
        backend.allowPosting();
        await tester.pumpAndSettle();
        expect(
          find.text('You cannot send messages in this channel.'),
          findsNothing,
        );
        expect(
          mobile
              ? find.byKey(const ValueKey('mobile-composer'))
              : find.byType(PlainMessageEditor),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
