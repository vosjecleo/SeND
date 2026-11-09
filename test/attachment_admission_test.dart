import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/attachment_admission.dart';

final _largeBytes = Uint8List(attachmentUploadBudget + 1);
AttachmentDraft draft(int size) => AttachmentDraft(
  bytes: size > 100 * 1048576
      ? Uint8List.sublistView(_largeBytes, 0, size)
      : Uint8List(size),
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
    '512 MiB per-file boundary is admitted and only oversized files are marked',
    () async {
      final exact = await prepareAttachmentBatch(
        [draft(attachmentUploadBudget)],
        const AppPreferences(),
        prepare: (item) async => item,
      );
      expect(exact.single.uploadTooLarge, false);
      try {
        await prepareAttachmentBatch(
          [draft(1), draft(attachmentUploadBudget + 1)],
          const AppPreferences(),
          prepare: (item) async => item,
        );
        fail('oversized batch admitted');
      } on AttachmentBudgetExceeded catch (error) {
        expect(error.attachments.length, 2);
        expect(error.attachments.map((item) => item.uploadTooLarge), [
          false,
          true,
        ]);
        expect(
          error.toString(),
          contains('Uh-oh! Your attachment is too big.'),
        );
      }
    },
  );
  test(
    'upload admission is per file rather than a 512 MiB batch total',
    () async {
      final files = await prepareAttachmentBatch(
        [draft(300 * 1048576), draft(300 * 1048576)],
        const AppPreferences(),
        prepare: (file) async => file,
      );
      expect(files.length, 2);
      expect(files.every((file) => !file.uploadTooLarge), true);
    },
  );
  test('large-upload warning is strictly above 128 MiB', () {
    expect(largeUploads([draft(attachmentWarningThreshold)]), isEmpty);
    expect(largeUploads([draft(attachmentWarningThreshold + 1)]).length, 1);
    validateAttachmentSelection([attachmentUploadBudget]);
  });
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
