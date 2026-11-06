import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/queued_attachment_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  late Uint8List bytes;
  AttachmentDraft? draft;
  @override
  AttachmentDraft? queuedAttachment(String id) => draft;
  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async => bytes;
}

void main() {
  for (final mobile in [false, true]) {
    for (final landscape in [false, true]) {
      testWidgets(
        'queued image matches delivered bounds: mobile=$mobile landscape=$landscape',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = mobile
              ? const Size(430, 900)
              : const Size(1440, 1000);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final width = landscape ? 80 : 40, height = landscape ? 40 : 80;
          final bytes = image.encodePng(
            image.Image(width: width, height: height),
          );
          const room = RoomSummary(
            id: 'room',
            name: 'Pending media',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          );
          final backend = _Backend()
            ..bytes = bytes
            ..draft = AttachmentDraft(
              bytes: bytes,
              name: 'photo.png',
              mimeType: 'image/png',
              spoiler: false,
            )
            ..currentStatus = SessionStatus.signedIn
            ..currentRoom = room
            ..roomList = [room];
          ChatMessage message(bool pending) => ChatMessage(
            id: 'media',
            sender: 'Upload author',
            senderId: '@me:test',
            body: '',
            timestamp: DateTime(2026, 11, 3, 12),
            pending: pending,
            queued: pending,
            own: true,
            attachment: ChatAttachment(
              kind: AttachmentKind.image,
              name: 'photo.png',
              mimeType: 'image/png',
              encrypted: false,
              spoiler: false,
              size: bytes.length,
              width: width,
              height: height,
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
          final pending = tester.getRect(
            find.byKey(const ValueKey('queued-attachment-frame')),
          );
          expect(find.byType(QueuedAttachmentPreview), findsOneWidget);
          expect(
            pending.left,
            closeTo(tester.getTopLeft(find.text('Upload author')).dx, .1),
          );
          final clip = tester.widget<ClipRRect>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('queued-attachment-frame')),
                  matching: find.byType(ClipRRect),
                )
                .first,
          );
          expect(clip.borderRadius, BorderRadius.circular(12));
          expect(pending.width / pending.height, closeTo(width / height, .001));

          backend.draft = null;
          backend.messageList = [message(false)];
          backend.notifyListeners();
          await tester.pumpAndSettle();
          final delivered = tester.getRect(find.byType(RawImage));
          expect(delivered.left, closeTo(pending.left, .1));
          expect(delivered.size.width, closeTo(pending.size.width, .1));
          expect(delivered.size.height, closeTo(pending.size.height, .1));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          backend.dispose();
        },
      );
    }
  }
}
