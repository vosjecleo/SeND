import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/attachment_admission.dart';

AttachmentDraft draft(int size) => AttachmentDraft(
  bytes: Uint8List(size),
  name: 'test.mp4',
  mimeType: 'video/mp4',
  spoiler: true,
);

void main() {
  test(
    'large originals can be selected; final compressed bytes determine admission',
    () async {
      validateAttachmentSelection([100 * 1048576]);
      final result = await prepareAttachmentBatch(
        [draft(100 * 1048576)],
        const AppPreferences(),
        prepare: (item) async => item.copyWith(bytes: Uint8List(12 * 1048576)),
      );
      expect(result.single.bytes.length, 12 * 1048576);
      expect(result.single.videoPrepared, true);
      expect(result.single.spoiler, true);
    },
  );
  test(
    '64 MiB exact is admitted, over-budget batch is retained and marked',
    () async {
      final exact = await prepareAttachmentBatch(
        [draft(attachmentUploadBudget)],
        const AppPreferences(),
        prepare: (item) async => item,
      );
      expect(exact.single.uploadTooLarge, false);
      try {
        await prepareAttachmentBatch(
          [draft(33 * 1048576), draft(33 * 1048576)],
          const AppPreferences(),
          prepare: (item) async => item,
        );
        fail('oversized batch admitted');
      } on AttachmentBudgetExceeded catch (error) {
        expect(error.attachments.length, 2);
        expect(error.attachments.every((item) => item.uploadTooLarge), true);
        expect(
          error.toString(),
          contains('Uh-oh! Your attachment is too big.'),
        );
      }
    },
  );
  test('read safety and file count remain separate limits', () {
    expect(
      () => validateAttachmentSelection([attachmentReadBudget + 1]),
      throwsStateError,
    );
    expect(
      () => validateAttachmentSelection(List.filled(21, 1)),
      throwsStateError,
    );
  });
}
