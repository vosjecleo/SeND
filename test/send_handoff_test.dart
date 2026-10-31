import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/queued_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  final gate = Completer<void>();
  String? transaction;
  @override
  bool get reconcilesOutgoingTransactions => true;
  @override
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    transaction = queuedTransactionId;
    await gate.future;
  }
}

class _MediaBackend extends FakeBackend {
  @override
  bool get reconcilesOutgoingTransactions => true;
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
  }) async {
    acknowledgeQueuedTransactions([queuedTransactionId!]);
  }
}

const _room = RoomSummary(
  id: 'room',
  name: 'Handoff chat',
  lastMessage: '',
  unreadCount: 0,
  usesChannelIcon: false,
);

void main() {
  test('repeated delivery cleanup preserves the uploaded file size', () {
    final message = QueuedMessage(
      id: 'local',
      room: 'room',
      body: '',
      sender: 'Me',
      senderId: '@me:test',
      draft: AttachmentDraft(
        name: 'clip.mp4',
        mimeType: 'video/mp4',
        spoiler: false,
        bytes: Uint8List(1024),
      ),
    );
    message.releaseUploadedFile();
    message.releaseUploadedFile();
    expect(message.draft!.bytes, isEmpty);
    expect(message.message.attachment!.size, 1024);
  });
  test(
    'handoff expiry starts at acknowledgement, not the time a send was queued',
    () {
      final message = QueuedMessage(
        id: 'local',
        room: 'room',
        body: 'Sent',
        sender: 'Me',
        senderId: '@me:test',
      );
      final now = DateTime.now();
      expect(message.handoffExpired(now.add(const Duration(days: 1))), isFalse);
      message.acknowledge();
      expect(
        message.handoffExpired(now.add(const Duration(minutes: 1))),
        isFalse,
      );
      expect(
        message.handoffExpired(now.add(const Duration(minutes: 3))),
        isTrue,
      );
    },
  );
  test(
    'SDK failed-send events replace their placeholder instead of staying queued',
    () async {
      final backend = _Backend()..currentRoom = _room;
      final sending = backend.submitComposerMessage(
        roomId: 'room',
        text: 'Needs retry',
      );
      final rejected = expectLater(sending, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      final local = backend.timelineMessages.single;
      backend.messageList = [
        ChatMessage(
          id: 'failed-event',
          transactionId: local.id,
          body: local.body,
          sender: local.sender,
          timestamp: local.timestamp,
          own: true,
          pending: false,
          failed: true,
        ),
      ];
      expect(backend.timelineMessages.single.failed, isTrue);
      backend.gate.completeError(StateError('offline'));
      await rejected;
      expect(backend.timelineMessages.single.id, 'failed-event');
      backend.dispose();
    },
  );
  for (final mobile in [false, true]) {
    for (final earlyAck in [false, true]) {
      testWidgets(
        'send stays visible at every handoff frame, mobile=$mobile earlyAck=$earlyAck',
        (tester) async {
          final backend = _Backend()
            ..currentStatus = SessionStatus.signedIn
            ..currentRoom = _room
            ..roomList = const [_room];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            await tester.pumpWidget(DeltiecordApp(backend: backend));
            await tester.pumpAndSettle();
          }
          final sending = backend.submitComposerMessage(
            roomId: 'room',
            text: 'Never disappear',
          );
          await tester.pump();
          final local = backend.timelineMessages.single;
          void visible({required bool pending}) {
            expect(find.text('Never disappear'), findsOneWidget);
            final opacity = find
                .ancestor(
                  of: find.text('Never disappear'),
                  matching: find.byType(Opacity),
                )
                .first;
            expect(tester.widget<Opacity>(opacity).opacity, pending ? .55 : 1);
            expect(find.textContaining('Queued'), findsNothing);
            expect(find.text('Sending'), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
          }

          visible(pending: true);
          backend.messageList = [
            ChatMessage(
              id: 'sdk-local',
              transactionId: local.id,
              body: local.body,
              sender: local.sender,
              timestamp: local.timestamp,
              own: true,
              pending: true,
            ),
          ];
          backend.notifyListeners();
          await tester.pump();
          visible(pending: true);
          if (earlyAck) backend.acknowledgeQueuedTransactions([local.id]);
          backend.gate.complete();
          await sending;
          if (!earlyAck) backend.acknowledgeQueuedTransactions([local.id]);
          for (var frame = 0; frame < 4; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            visible(pending: true);
          }
          backend.messageList = [
            ChatMessage(
              id: 'server-event',
              transactionId: local.id,
              body: 'Unable to decrypt this message',
              sender: local.sender,
              timestamp: local.timestamp,
              own: true,
              pending: false,
              decryptionPending: true,
            ),
          ];
          backend.notifyListeners();
          await tester.pump();
          visible(pending: true);
          expect(find.text('Unable to decrypt this message'), findsNothing);
          final remote = ChatMessage(
            id: 'server-event',
            transactionId: local.id,
            body: local.body,
            sender: local.sender,
            timestamp: local.timestamp,
            own: true,
            pending: false,
          );
          expect(remote.timelineKey, local.timelineKey);
          backend.messageList = [remote];
          backend.notifyListeners();
          await tester.pump();
          visible(pending: false);
          expect(backend.timelineMessages.single.id, 'server-event');
          await tester.pumpWidget(const SizedBox());
          backend.dispose();
        },
      );
    }
  }

  test(
    'foreign transaction IDs cannot suppress a pending send or borrow its UI key',
    () async {
      final backend = _Backend()..currentRoom = _room;
      final sending = backend.submitComposerMessage(
        roomId: 'room',
        text: 'Mine',
      );
      final local = backend.timelineMessages.single;
      final foreign = ChatMessage(
        id: 'foreign',
        transactionId: local.id,
        body: 'Other',
        sender: 'Other',
        timestamp: local.timestamp,
        pending: false,
      );
      final projection = backend.conversationMessages(
        roomId: 'room',
        sent: [foreign],
      );
      expect(projection.map((m) => m.body), ['Mine', 'Other']);
      expect(foreign.timelineKey, 'foreign');
      backend.gate.complete();
      await sending;
      backend.cancelQueuedSends();
      expect(backend.timelineMessages, isEmpty);
      backend.dispose();
    },
  );

  test(
    'an acknowledged send is not retried when its HTTP response is lost',
    () async {
      final backend = _Backend()..currentRoom = _room;
      final sending = backend.submitComposerMessage(
        roomId: 'room',
        text: 'Delivered',
      );
      await Future<void>.delayed(Duration.zero);
      final id = backend.timelineMessages.single.id;
      backend.acknowledgeQueuedTransactions([id]);
      backend.gate.completeError(StateError('response lost'));
      await sending;
      expect(backend.timelineMessages.single.body, 'Delivered');
      backend.dispose();
    },
  );

  test(
    'acknowledged preview media is bounded and uploaded video bytes are released',
    () async {
      final backend = _MediaBackend()..currentRoom = _room;
      for (var index = 0; index < 2; index++) {
        await backend.submitComposerMessage(
          roomId: 'room',
          text: '',
          attachments: [
            AttachmentDraft(
              name: 'photo$index.png',
              mimeType: 'image/png',
              spoiler: true,
              bytes: Uint8List(34 * 1024 * 1024),
            ),
          ],
        );
      }
      expect(backend.timelineMessages, hasLength(1));
      backend.cancelQueuedSends();
      await backend.submitComposerMessage(
        roomId: 'room',
        text: '',
        attachments: [
          AttachmentDraft(
            name: 'clip.mp4',
            mimeType: 'video/mp4',
            spoiler: true,
            bytes: Uint8List(1024),
            videoThumbnail: Uint8List(4),
          ),
        ],
      );
      final local = backend.timelineMessages.single;
      expect(local.attachment!.size, 1024);
      expect(backend.queuedAttachment(local.id)!.bytes, isEmpty);
      expect(backend.queuedAttachment(local.id)!.videoThumbnail, hasLength(4));
      backend.dispose();
    },
  );
}
