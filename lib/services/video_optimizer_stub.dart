import '../models/chat_models.dart';

bool get videoOptimizationSupported => false;
Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
}) async => draft;
