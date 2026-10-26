import 'dart:async';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'composer submits another message during a pending send, mobile=$mobile',
      (tester) async {
        final gate = Completer<void>();
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..sendGate = gate
          ..roomList = const [
            RoomSummary(
              id: '!r:test',
              name: 'Queue test',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
        }
        await tester.tap(find.text('Queue test'));
        await tester.pumpAndSettle();
        Future<void> enter(String text) async {
          if (mobile) {
            await tester.enterText(
              find.byKey(const ValueKey('mobile-composer-field')),
              text,
            );
            await tester.pump();
          } else {
            await enterComposer(tester, text);
          }
        }

        Future<void> send() async {
          await tester.tap(
            mobile ? find.byIcon(Icons.send).last : find.byTooltip('Send'),
          );
          await tester.pump();
        }

        await enter('first');
        await send();
        await enter('second');
        await send();
        expect(backend.sentMessages, ['first']);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byIcon(Icons.send), findsWidgets);
        await enter('third draft');
        gate.complete();
        await tester.pumpAndSettle();
        expect(backend.sentMessages, ['first', 'second']);
        final draft = mobile
            ? tester
                  .widget<TextField>(
                    find.byKey(const ValueKey('mobile-composer-field')),
                  )
                  .controller!
                  .text
            : tester
                  .widget<PlainMessageEditor>(find.byType(PlainMessageEditor))
                  .controller
                  .document
                  .toPlainText()
                  .trim();
        expect(draft, 'third draft');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
