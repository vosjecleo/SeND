import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'composer grows on the first rendered wrap and keeps insets, mobile=$mobile scale=$scale',
        (tester) async {
          const room = RoomSummary(
            id: 'room',
            name: 'Wrapping',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          );
          final backend = FakeBackend()
            ..currentStatus = SessionStatus.signedIn
            ..currentRoom = room
            ..roomList = const [room]
            ..currentPreferences = AppPreferences(fontScale: scale);
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            tester.view.physicalSize = const Size(1000, 800);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(DeltiecordApp(backend: backend));
            await tester.pumpAndSettle();
          }
          final field = find.byKey(
            ValueKey(mobile ? 'mobile-composer-field' : 'plain-message-editor'),
          );
          final surface = find.byKey(
            ValueKey(
              mobile
                  ? 'mobile-composer-field-surface'
                  : 'plain-message-editor-surface',
            ),
          );
          Rect caret(int offset) {
            final editable = tester
                .state<EditableTextState>(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                )
                .renderEditable;
            return MatrixUtils.transformRect(
              editable.getTransformTo(null),
              editable.getLocalRectForCaret(TextPosition(offset: offset)),
            );
          }

          await tester.enterText(field, 'W');
          await tester.pumpAndSettle();
          final initial = tester.getRect(surface);
          final padding = tester
              .widget<Padding>(surface)
              .padding
              .resolve(TextDirection.ltr);
          expect(padding.top, greaterThan(4));
          expect(padding.bottom, greaterThan(4));
          final topInset = caret(0).top - initial.top;
          final bottomInset = initial.bottom - caret(1).bottom;
          expect(topInset, greaterThan(4));
          expect(bottomInset, greaterThan(4));
          var boundary = 0;
          for (var length = 2; length < 100; length++) {
            await tester.enterText(field, 'W' * length);
            await tester.pump();
            if (caret(length).top > caret(0).top + 1) {
              boundary = length;
              final frame = tester.getRect(surface);
              expect(frame.height, greaterThan(initial.height + 5));
              expect(
                caret(0).top - frame.top,
                greaterThanOrEqualTo(padding.top - 1),
              );
              expect(
                frame.bottom - caret(length).bottom,
                greaterThanOrEqualTo(padding.bottom - 1),
              );
              break;
            }
          }
          expect(boundary, greaterThan(0));
          await tester.enterText(field, 'W' * (boundary - 1));
          await tester.pumpAndSettle();
          expect(tester.getSize(surface).height, closeTo(initial.height, 1));
          await tester.enterText(field, 'First\nSecond');
          await tester.pumpAndSettle();
          final manual = tester.getRect(surface);
          expect(
            caret(0).top - manual.top,
            greaterThanOrEqualTo(padding.top - 1),
          );
          expect(
            manual.bottom - caret('First\nSecond'.length).bottom,
            greaterThanOrEqualTo(padding.bottom - 1),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
