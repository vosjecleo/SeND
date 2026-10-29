import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/queued_message.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class OutboxBackend extends FakeBackend {
  final prepared = Completer<void>();
  final sent = <String>[];
  int? failAt;
  int attempts = 0;
  @override
  bool get reconcilesOutgoingTransactions => true;
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> drafts, {
    void Function(int index, String status, double? progress)? onProgress,
  }) async {
    onProgress?.call(0, 'Compressing', .3);
    await prepared.future;
    return drafts;
  }

  void acknowledge(String body) {
    final transaction = queuedTransactionId;
    messageList = [
      ChatMessage(
        id: 'remote-${sent.length}',
        transactionId: transaction,
        body: body,
        sender: 'You',
        own: true,
        pending: false,
        timestamp: DateTime.now(),
      ),
      ...messageList,
    ];
    notifyListeners();
  }

  @override
  Future<void> sendMessage(
    String text, {
    String? roomId,
    String? formattedBody,
    String? replyToMessageId,
    String? editMessageId,
  }) async {
    sent.add(text);
    acknowledge(text);
  }

  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    attempts++;
    if (failAt == attempts) throw StateError('upload fixture');
    sent.add(attachment.name);
    acknowledge(attachment.caption ?? '');
  }
}

const room = RoomSummary(
  id: 'room',
  name: 'Chat',
  lastMessage: '',
  unreadCount: 0,
  usesChannelIcon: false,
);
AttachmentDraft draft(String name, String mime) => AttachmentDraft(
  bytes: Uint8List(10),
  name: name,
  mimeType: mime,
  spoiler: true,
);
void main() {
  for (final mime in ['image/png', 'video/mp4']) {
    test(
      'pending $mime appears before preparation and reconciles without duplicates',
      () async {
        final backend = OutboxBackend()..currentRoom = room;
        final first = backend.submitComposerMessage(
          roomId: 'room',
          text: 'caption',
          attachments: [draft('media', mime)],
        );
        expect(backend.timelineMessages.single.pending, true);
        expect(
          backend.queuedAttachment(backend.timelineMessages.single.id)?.spoiler,
          true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(backend.timelineMessages.single.preparationProgress, .3);
        expect(
          MediaAlbumIndex.fromNewestFirst(backend.timelineMessages).albums,
          isEmpty,
        );
        final next = backend.submitComposerMessage(
          roomId: 'room',
          text: 'next',
        );
        expect(backend.timelineMessages.map((m) => m.body), [
          'next',
          'caption',
        ]);
        expect(backend.sent, isEmpty);
        backend.prepared.complete();
        await Future.wait([first, next]);
        expect(backend.sent, ['media', 'next']);
        expect(backend.timelineMessages.length, 2);
        expect(backend.timelineMessages.any((m) => m.pending), false);
        backend.dispose();
      },
    );
  }
  test('partial batch failure only returns unsent attachments', () async {
    final backend = OutboxBackend()
      ..currentRoom = room
      ..failAt = 2;
    backend.prepared.complete();
    Object? failure;
    try {
      await backend.submitComposerMessage(
        roomId: 'room',
        text: 'caption',
        attachments: [
          draft('one', 'application/pdf'),
          draft('two', 'application/pdf'),
        ],
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<PartialComposerSendFailure>());
    final remaining = (failure as PartialComposerSendFailure).attachments;
    expect(remaining.map((a) => a.name), ['two']);
    await backend.submitComposerMessage(
      roomId: 'room',
      text: '',
      attachments: remaining,
    );
    expect(backend.sent, ['one', 'two']);
    backend.dispose();
  });
  test('discard during preparation does not upload later', () async {
    final backend = OutboxBackend()..currentRoom = room;
    final send = backend.submitComposerMessage(
      roomId: 'room',
      text: '',
      attachments: [draft('one', 'image/png')],
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      backend.cancelLocalQueuedMessage(backend.timelineMessages.single.id),
      true,
    );
    backend.prepared.complete();
    await send;
    expect(backend.sent, isEmpty);
    expect(backend.timelineMessages, isEmpty);
    backend.dispose();
  });
}
