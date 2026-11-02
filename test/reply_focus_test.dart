import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'draft reply and two jump pulses override then restore mention colour, mobile=$mobile',
      (tester) async {
        final backend = FakeBackend()
          ..currentStatus = SessionStatus.signedIn
          ..currentPreferences = const AppPreferences(reducedMotion: true)
          ..roomList = const [
            RoomSummary(
              id: '!room:test',
              name: 'Reply focus',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
            ),
          ]
          ..messageList = [
            ChatMessage(
              id: 'target',
              sender: 'Friend',
              body: 'Target message',
              timestamp: DateTime(2026),
              pending: false,
              pingedCurrentUser: true,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Reply focus'));
        await tester.pumpAndSettle();
        Color? colour() => mobile
            ? (tester
                          .widget<DecoratedBox>(
                            find.byKey(
                              const ValueKey('message-highlight-target'),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .color
            : (tester
                          .widget<AnimatedContainer>(
                            find.byKey(const Key('message-row-target')),
                          )
                          .decoration
                      as BoxDecoration)
                  .color;
        final original = colour();
        if (mobile) {
          await tester.drag(
            find.byKey(const ValueKey('swipe-target')),
            const Offset(-160, 0),
          );
          await tester.pumpAndSettle();
        } else {
          await revealMessageActions(tester, find.text('Target message'));
          await tester.tap(find.byKey(const Key('message-action-reply')));
          await tester.pumpAndSettle();
        }
        final selected = const Color(0xff408cff).withValues(alpha: .17);
        final flash = tester
            .element(
              find.byKey(
                mobile
                    ? const ValueKey('message-highlight-target')
                    : const Key('message-row-target'),
              ),
            )
            .deltiecord
            .hover;
        expect(colour(), selected);
        await tester.tap(find.text('Replying to Friend'));
        Future<void> waitForColour(Color expected) async {
          for (var frame = 0; frame < 40 && colour() != expected; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
          expect(colour(), expected);
        }

        await waitForColour(flash);
        await waitForColour(selected);
        await waitForColour(flash);
        await waitForColour(selected);
        await tester.tap(
          mobile
              ? find.descendant(
                  of: find.byKey(const ValueKey('mobile-composer')),
                  matching: find.byIcon(Icons.close),
                )
              : find.byTooltip('Cancel'),
        );
        await tester.pumpAndSettle();
        expect(colour(), original);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
