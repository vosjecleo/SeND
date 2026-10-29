import '../models/chat_models.dart';
import 'image_preparation.dart';
import 'video_preparation.dart';

const attachmentUploadBudget = 64 * 1024 * 1024;
// Originals are held in memory by the existing editor. This is a read-safety
// bound, not an upload allowance; the final 64 MiB budget still applies.
const attachmentReadBudget = 256 * 1024 * 1024;
const attachmentCountLimit = 20;

void validateAttachmentSelection(Iterable<int> sizes) {
  final values = sizes.toList();
  if (values.length > attachmentCountLimit) {
    throw StateError('Choose at most 20 files.');
  }
  if (values.fold<int>(0, (a, b) => a + b) > attachmentReadBudget) {
    throw StateError('Select fewer files to edit safely (256 MiB at a time).');
  }
}

class AttachmentBudgetExceeded implements Exception {
  AttachmentBudgetExceeded(List<AttachmentDraft> drafts)
    : attachments = List.unmodifiable(
        drafts.map((draft) => draft.copyWith(uploadTooLarge: true)),
      );
  final List<AttachmentDraft> attachments;
  @override
  String toString() =>
      'Uh-oh! Your attachment is too big.\nSelect a (smaller) compression option or try another way';
}

Future<List<AttachmentDraft>> prepareAttachmentBatch(
  List<AttachmentDraft> drafts,
  AppPreferences preferences, {
  Future<AttachmentDraft> Function(AttachmentDraft)? prepare,
  void Function(int index, String status, double? progress)? onProgress,
}) async {
  if (drafts.length > attachmentCountLimit) {
    throw StateError('Send at most 20 files at a time.');
  }
  final prepared = <AttachmentDraft>[];
  for (final draft in drafts) {
    final index = prepared.length;
    var item = draft;
    if (prepare != null) {
      item = await prepare(item);
    } else {
      if (draft.mimeType.startsWith('image/') && !draft.imagePrepared) {
        onProgress?.call(index, 'Compressing image', null);
        await Future<void>.delayed(Duration.zero);
      }
      item = await prepareImage(item, preferences.imageCompression);
      if (preferences.optimizeVideos && !item.videoPrepared) {
        void changed() => onProgress?.call(
          index,
          'Compressing video',
          VideoPreparation.instance.progress,
        );
        VideoPreparation.instance.addListener(changed);
        try {
          item = await VideoPreparation.instance.prepare(
            item,
            preset: preferences.videoCompression,
          );
        } finally {
          VideoPreparation.instance.removeListener(changed);
        }
      } else if (item.mimeType.startsWith('video/') && !item.videoPrepared) {
        item = await VideoPreparation.probe(item);
      }
    }
    onProgress?.call(index, 'Waiting to upload', null);
    // A prepared batch must not be encoded again between admission and upload.
    prepared.add(
      item.copyWith(
        imagePrepared: item.mimeType.startsWith('image/') || item.imagePrepared,
        videoPrepared: item.mimeType.startsWith('video/') || item.videoPrepared,
        uploadTooLarge: false,
      ),
    );
  }
  if (prepared.fold<int>(0, (total, item) => total + item.bytes.length) >
      attachmentUploadBudget) {
    throw AttachmentBudgetExceeded(prepared);
  }
  return prepared;
}
