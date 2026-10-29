import 'dart:async';
import 'dart:typed_data';
import '../models/chat_models.dart';

final _transactionZone = Object();

class PartialComposerSendFailure implements Exception {
  PartialComposerSendFailure(this.attachments, this.cause);
  final List<AttachmentDraft> attachments;
  final Object cause;
  @override
  String toString() =>
      'Some attachments were not sent. The remaining attachments were kept.';
}

String? get queuedTransactionId => Zone.current[_transactionZone] as String?;
Future<T> withQueuedTransaction<T>(String id, Future<T> Function() send) =>
    runZoned(send, zoneValues: {_transactionZone: id});

class QueuedMessage {
  QueuedMessage({
    required this.id,
    required this.room,
    required this.body,
    required this.sender,
    required this.senderId,
    this.avatar,
    this.draft,
    this.formattedBody,
    this.reply,
  });
  final String id, room, body, sender;
  final String? senderId, formattedBody;
  final Uint8List? avatar;
  final ReplyPreview? reply;
  final DateTime timestamp = DateTime.now();
  AttachmentDraft? draft;
  String status = 'Waiting to send';
  double? progress;
  bool completed = false;
  bool cancelled = false;
  ChatMessage get message => ChatMessage(
    id: id,
    sender: sender,
    senderId: senderId,
    avatarBytes: avatar,
    body: body,
    formattedBody: formattedBody,
    timestamp: timestamp,
    pending: true,
    queued: true,
    own: true,
    reply: reply,
    transferStatus: status,
    preparationProgress: progress,
    attachment: draft == null
        ? null
        : ChatAttachment(
            kind: draft!.mimeType.startsWith('image/')
                ? AttachmentKind.image
                : draft!.mimeType.startsWith('video/')
                ? AttachmentKind.video
                : draft!.mimeType.startsWith('audio/')
                ? AttachmentKind.audio
                : AttachmentKind.file,
            name: draft!.name,
            mimeType: draft!.mimeType,
            size: draft!.bytes.length,
            encrypted: true,
            spoiler: draft!.spoiler,
            caption: body.isEmpty ? null : body,
            width: draft!.videoWidth,
            height: draft!.videoHeight,
          ),
  );
}
