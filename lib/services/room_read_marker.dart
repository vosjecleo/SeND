import 'package:matrix/matrix.dart';

/// Keep the account's unread state current independently of public receipts.
Future<void> acknowledgeRoom(
  Room room,
  String eventId, {
  required bool sendPublicReceipts,
  required bool mainThreadOnly,
}) async {
  if (mainThreadOnly) {
    await room.client.postReceipt(
      room.id,
      ReceiptType.mReadPrivate,
      eventId,
      threadId: 'main',
    );
    if (sendPublicReceipts) {
      await room.client.postReceipt(
        room.id,
        ReceiptType.mRead,
        eventId,
        threadId: 'main',
      );
    }
    await room.setReadMarker(eventId);
  } else {
    await room.setReadMarker(
      eventId,
      mRead: eventId,
      public: sendPublicReceipts,
    );
  }
}
