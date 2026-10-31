import 'dart:convert';
import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'stickers align with message text (${mobile ? 'mobile' : 'desktop'})',
      (tester) async {
        tester.view.physicalSize = Size(mobile ? 430 : 1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const room = RoomSummary(
          id: '!stickers:example.org',
          name: 'Stickers test',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final backend = _ImageBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = [room]
          ..currentRoom = room
          ..messageList = [
            ChatMessage(
              id: 'sticker',
              sender: 'Alice',
              body: '',
              timestamp: DateTime(2026, 9, 22),
              pending: false,
              attachment: const ChatAttachment(
                kind: AttachmentKind.image,
                name: 'cat',
                mimeType: 'image/png',
                size: 70,
                encrypted: false,
                spoiler: false,
                sticker: true,
                width: 1,
                height: 1,
              ),
            ),
          ];
        await tester.pumpWidget(
          DeltiecordApp(
            backend: backend,
            platformOverride: mobile
                ? TargetPlatform.android
                : TargetPlatform.linux,
          ),
        );
        await tester.pumpAndSettle();
        if (mobile &&
            find
                .byKey(const ValueKey('mobile-message-content-sticker'))
                .evaluate()
                .isEmpty) {
          await tester.tap(find.text('Stickers test').first);
          await tester.pumpAndSettle();
        }
        final content = find.byKey(
          ValueKey('${mobile ? 'mobile-' : ''}message-content-sticker'),
        );
        final frame = find.byKey(
          ValueKey(
            mobile ? 'mobile-image-frame-sticker' : 'sticker-frame-sticker',
          ),
        );
        expect(tester.getTopLeft(frame).dx, tester.getTopLeft(content).dx);
        expect(tester.getSize(frame).width, lessThanOrEqualTo(128));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

class _ImageBackend extends FakeBackend {
  @override
  Future<Uint8List> downloadAttachment(
    String messageId, {
    bool thumbnail = false,
  }) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/hK0P7wAAAABJRU5ErkJggg==',
  );
}
