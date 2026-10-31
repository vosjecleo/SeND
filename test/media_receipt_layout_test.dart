import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/message_metadata.dart';

void main() {
  testWidgets(
    'crowded media receipt moves to group header without reducing its width',
    (tester) async {
      late ReceiptPlacementScope placement;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              child: ReceiptPlacement(
                messages: [
                  message('media', media: attachment),
                  message('header', body: 'Hello'),
                ],
                receiptIds: const {'media'},
                contentInset: 80,
                child: Builder(
                  builder: (context) {
                    placement = ReceiptPlacementScope.of(context)!;
                    return SizedBox(
                      width: 320,
                      child: MediaWithMessageMetadata(
                        message: message('media', media: attachment),
                        showReceipt: true,
                        child: const SizedBox(width: 320, height: 200),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(placement.relocated, contains('media'));
      expect(placement.headers['header']!.single.id, 'media');
    },
  );
}

const attachment = ChatAttachment(
  kind: AttachmentKind.image,
  name: 'secret.png',
  mimeType: 'image/png',
  size: 1,
  encrypted: true,
  spoiler: true,
  width: 800,
  height: 400,
);

ChatMessage message(String id, {ChatAttachment? media, String body = ''}) =>
    ChatMessage(
      id: id,
      sender: 'Alice',
      senderId: '@alice:test',
      body: body,
      timestamp: DateTime(2026, 9, 24),
      pending: false,
      own: true,
      attachment: media,
    );
