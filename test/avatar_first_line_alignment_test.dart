import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  @override
  Future<Uint8List?> loadStickerPreview(StickerSummary sticker) async =>
      image.encodePng(image.Image(width: 1, height: 1));
}

void main() {
  for (final mobile in [false, true]) {
    for (final scale in [1.0, 1.4]) {
      testWidgets(
        'avatars stay at first line for jumbo emoji and tall text: mobile=$mobile scale=$scale',
        (tester) async {
          const room = RoomSummary(
            id: 'room',
            name: 'Avatar alignment',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          );
          final backend = _Backend()
            ..currentStatus = SessionStatus.signedIn
            ..roomList = [room]
            ..currentPreferences = AppPreferences(
              fontScale: scale,
              reducedMotion: true,
            );
          Future<void> setMessage(String text, [String? html]) async {
            backend.messageList = [
              ChatMessage(
                id: 'same-entry',
                sender: 'Sender',
                senderId: '@peer:test',
                body: text,
                formattedBody: html,
                timestamp: DateTime(2026, 11, 3, 12),
                pending: false,
              ),
            ];
            backend.notifyListeners();
            await tester.pumpAndSettle();
          }

          backend.messageList = [
            ChatMessage(
              id: 'same-entry',
              sender: 'Sender',
              senderId: '@peer:test',
              body: 'Short text',
              timestamp: DateTime(2026, 11, 3, 12),
              pending: false,
            ),
          ];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            // Web switches to the mobile timeline at narrow widths. Exercise
            // an actual desktop viewport when checking desktop avatar keys.
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = const Size(1440, 1000);
            addTearDown(() {
              tester.view.resetDevicePixelRatio();
              tester.view.resetPhysicalSize();
            });
            await tester.pumpWidget(
              DeltiecordApp(
                backend: backend,
                platformOverride: TargetPlatform.linux,
              ),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(find.text(room.name));
          await tester.pumpAndSettle();
          final avatar = find.byKey(
            ValueKey(
              mobile
                  ? 'mobile-message-avatar-same-entry'
                  : 'message-avatar-same-entry',
            ),
          );
          final body = find.byKey(
            ValueKey(
              mobile
                  ? 'mobile-message-body-same-entry'
                  : 'message-body-same-entry',
            ),
          );
          double relativeCenter() =>
              tester.getCenter(avatar).dy -
              tester.getTopLeft(find.text('Sender')).dy;
          final firstLineCenter = relativeCenter();
          for (final value in <(String, String?)>[
            ('👍', null),
            (
              ':cat:',
              '<img data-mx-emoticon src="mxc://test/cat" alt=":cat:">',
            ),
            (List.filled(100, 'wrapped words').join(' '), null),
            ('First\nSecond\nThird', '<p>First</p><p>Second</p><p>Third</p>'),
          ]) {
            await setMessage(value.$1, value.$2);
            expect(relativeCenter(), closeTo(firstLineCenter, 2.5));
            expect(
              tester.getCenter(avatar).dy,
              lessThan(tester.getRect(body).center.dy),
            );
            expect(tester.takeException(), isNull);
          }
          await setMessage(
            ':cat: inline',
            '<img data-mx-emoticon src="mxc://test/cat" alt=":cat:"> inline',
          );
          final senderTop = tester.getTopLeft(find.text('Sender')).dy;
          expect(
            tester.getCenter(avatar).dy,
            closeTo((senderTop + tester.getRect(body).bottom) / 2, 1),
          );
          await setMessage('Short text');
          expect(relativeCenter(), closeTo(firstLineCenter, .1));
          await tester.pumpWidget(const SizedBox());
          if (kIsWeb) {
            // Let the bounded browser startup request finish after teardown.
            // pumpAndSettle alone does not advance an idle network timeout.
            await tester.pump(const Duration(seconds: 8));
          }
        },
      );
    }
  }
}
