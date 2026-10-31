import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/queued_attachment_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _UploadBackend extends FakeBackend {
  final upload = Completer<void>();
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> drafts, {
    void Function(int, String, double?)? onProgress,
  }) async => drafts;
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) => upload.future;
}

void main() {
  for (final mobile in [false, true]) {
    for (final video in [false, true]) {
      testWidgets(
        'upload has one top progress bar, mobile=$mobile video=$video',
        (tester) async {
          const room = RoomSummary(
            id: 'room',
            name: 'Uploads',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          );
          final backend = _UploadBackend()
            ..currentStatus = SessionStatus.signedIn
            ..currentRoom = room
            ..roomList = const [room];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            await tester.pumpWidget(DeltiecordApp(backend: backend));
            await tester.pumpAndSettle();
          }
          final name = video ? 'clip.mp4' : 'photo.png';
          final sending = backend.submitComposerMessage(
            roomId: room.id,
            text: '',
            attachments: [
              AttachmentDraft(
                name: name,
                bytes: Uint8List(4),
                mimeType: video ? 'video/mp4' : 'image/png',
                spoiler: true,
                imagePrepared: true,
                videoPrepared: true,
              ),
            ],
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('Uploading $name'), findsOneWidget);
          final bar = find.byType(LinearProgressIndicator);
          expect(bar, findsOneWidget);
          expect(
            tester.getRect(bar).center.dy,
            lessThan(tester.getRect(find.byType(QueuedAttachmentPreview)).top),
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);
          // Cancelling a local preparation must not pretend it can cancel an
          // already-started Matrix upload.
          expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
          backend.upload.complete();
          await sending;
          await tester.pumpAndSettle();
          expect(find.text('Uploading $name'), findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          await tester.pumpWidget(const SizedBox());
          backend.dispose();
        },
      );
    }
  }
}
