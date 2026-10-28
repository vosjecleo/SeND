import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../models/video_edit.dart';

bool get videoOptimizationSupported => false;
Future<AttachmentDraft> probeVideo(AttachmentDraft draft) async => draft;
Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
  VideoCompressionPreset preset = VideoCompressionPreset.balanced,
  bool optimize = true,
  VideoEditPlan? edit,
}) async {
  if (edit?.hasChanges == true) {
    throw UnsupportedError('Video editing is unavailable on this platform.');
  }
  return draft;
}
