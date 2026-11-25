import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/chat_notifications.dart';
import 'package:deltiecord/ui/settings_screen.dart';
import 'package:deltiecord/ui/chat_shell.dart'
    show ThreadView, openDiscussionById;
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  int revision = 0;
  @override
  int get notificationNavigationRevision => revision;
  Future<void> activate(String id) async {
    setConversationVisible(false);
    revision++;
    notifyListeners();
    await selectRoom(id);
  }
}

void main() {
  for (final sameRoom in [false, true]) {
    for (final thread in [false, true]) {
      testWidgets(
        'notification dismisses Settings/forum post and dialogs, same room=$sameRoom thread=$thread',
        (tester) async {
          final backend = _Backend()
            ..currentStatus = SessionStatus.signedIn
            ..roomList = const [
              RoomSummary(
                id: 'a',
                name: 'Alice',
                lastMessage: '',
                unreadCount: 0,
                usesChannelIcon: false,
                isDirect: true,
              ),
              RoomSummary(
                id: 'b',
                name: 'Bob',
                lastMessage: '',
                unreadCount: 1,
                usesChannelIcon: false,
                isDirect: true,
              ),
            ];
          addTearDown(backend.dispose);
          addTearDown(InAppNotificationCenter.dismiss);
          await pumpMobile(tester, backend);
          await tester.tap(find.text('Alice'));
          await tester.pumpAndSettle();
          if (thread) {
            openDiscussionById(
              tester.element(find.byKey(const ValueKey('mobile-timeline'))),
              backend,
              'a',
              r'$root',
            );
          } else {
            unawaited(
              showDeltiecordSettings(
                tester.element(
                  find.byKey(const ValueKey('mobile-user-island')),
                ),
                backend,
              ),
            );
          }
          await tester.pumpAndSettle();
          final settings = tester.element(
            thread ? find.byType(ThreadView) : find.byTooltip('Close settings'),
          );
          unawaited(
            showDialog<void>(
              context: settings,
              builder: (_) => const AlertDialog(title: Text('Open popup')),
            ),
          );
          await tester.pumpAndSettle();
          final target = sameRoom ? 'a' : 'b';
          InAppNotificationCenter.show(
            InAppChatNotification(
              roomId: target,
              title: 'Open conversation',
              body: 'Message',
              onTap: () {
                InAppNotificationCenter.dismiss();
                unawaited(backend.activate(target));
              },
            ),
          );
          await tester.pump();
          await tester.tap(find.text('Open conversation'));
          await tester.pumpAndSettle();
          expect(find.text('Open popup'), findsNothing);
          expect(find.byTooltip('Close settings'), findsNothing);
          expect(find.byType(ThreadView), findsNothing);
          expect(backend.selectedRoom?.id, target);
          expect(backend.conversationVisibilityStates.last, true);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
