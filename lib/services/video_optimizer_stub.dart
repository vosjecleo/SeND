import '../models/chat_models.dart';
import '../models/media_compression.dart';

bool get videoOptimizationSupported => false;
Future<AttachmentDraft> probeVideo(AttachmentDraft draft) async => draft;
Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
  VideoCompressionPreset preset = VideoCompressionPreset.balanced,
}) async => draft;
