import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    for (final channel in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          'chat columns align: mobile=$mobile channel=$channel scale=$scale',
          (tester) async {
            final room = RoomSummary(
              id: 'room',
              name: 'Alignment chat',
              topic: 'Channel description',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: channel,
              isDirect: !channel,
              directUserId: channel ? null : '@peer:test',
            );
            final backend = FakeBackend()
              ..currentStatus = SessionStatus.signedIn
              ..roomList = [room]
              ..currentPreferences = AppPreferences(
                fontScale: scale,
                reducedMotion: true,
              )
              ..typingNames = ['Peer']
              ..messageList = [
                ChatMessage(
                  id: 'entry',
                  sender: 'Sender column',
                  senderId: '@peer:test',
                  body: 'Message column',
                  timestamp: DateTime(2026),
                  pending: false,
                ),
              ];
            if (mobile) {
              await pumpMobile(tester, backend);
            } else {
              tester.view.physicalSize = const Size(1600, 1000);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              await tester.pumpWidget(DeltiecordApp(backend: backend));
              await tester.pumpAndSettle();
            }
            await tester.tap(find.text(room.name));
            await tester.pumpAndSettle();
            final senderX = tester.getTopLeft(find.text('Sender column')).dx;
            final body = find.byKey(
              ValueKey(
                mobile ? 'mobile-message-body-entry' : 'message-body-entry',
              ),
            );
            expect(tester.getTopLeft(body).dx, closeTo(senderX, .1));
            final avatar = tester.getRect(
              find.byKey(
                ValueKey(
                  mobile
                      ? 'mobile-message-avatar-entry'
                      : 'message-avatar-entry',
                ),
              ),
            );
            final typing = tester.getRect(
              find.byKey(const ValueKey('typing-indicator-label')),
            );
            final middleDot = tester.getCenter(
              find.byKey(const ValueKey('typing-dot-1')),
            );
            expect(typing.left, closeTo(senderX, .1));
            expect(middleDot.dx, closeTo(avatar.center.dx, .1));
            if (mobile) {
              final timeline = tester.getRect(
                find.byKey(const ValueKey('mobile-timeline')),
              );
              expect(
                avatar.center.dx,
                closeTo((timeline.left + senderX) / 2, .1),
              );
              final field = find.byKey(const ValueKey('mobile-composer-field'));
              await tester.enterText(field, 'Draft');
              await tester.pump();
              final editable = tester
                  .state<EditableTextState>(
                    find.descendant(
                      of: field,
                      matching: find.byType(EditableText),
                    ),
                  )
                  .renderEditable;
              final caret = MatrixUtils.transformRect(
                editable.getTransformTo(null),
                editable.getLocalRectForCaret(const TextPosition(offset: 0)),
              );
              expect(caret.left, closeTo(senderX, .1));
            }
            if (channel || !mobile) {
              final name = find.byKey(
                const ValueKey('conversation-header-name'),
              );
              final headerX = channel && !mobile ? avatar.left : senderX;
              expect(tester.getTopLeft(name).dx, closeTo(headerX, .1));
              if (channel) {
                expect(
                  find.byKey(const ValueKey('conversation-header-avatar')),
                  findsNothing,
                );
                expect(
                  tester
                      .getTopLeft(
                        find.byKey(const ValueKey('conversation-header-topic')),
                      )
                      .dx,
                  closeTo(headerX, .1),
                );
              } else {
                final header = tester.getRect(
                  find.byKey(const ValueKey('conversation-header-avatar')),
                );
                expect(header.left, closeTo(avatar.left, .1));
                expect(header.width, closeTo(avatar.width, .1));
              }
            }
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
