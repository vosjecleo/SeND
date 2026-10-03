import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import 'video_optimizer.dart';

enum VideoRecovery { retry, original, cancel }

typedef VideoOptimizer =
    Future<AttachmentDraft> Function(
      AttachmentDraft draft, {
      required void Function(double) progress,
      required bool Function() canceled,
    });

class VideoPreparation extends ChangeNotifier {
  VideoPreparation({VideoOptimizer? optimizer, bool? supported})
    : _optimizer = optimizer ?? optimizeVideo,
      _supported = supported ?? videoOptimizationSupported;
  final VideoOptimizer _optimizer;
  final bool _supported;
  static Future<AttachmentDraft> probe(AttachmentDraft draft) =>
      probeVideo(draft);
  static final instance = VideoPreparation();
  bool active = false;
  bool _canceled = false;
  double progress = 0;
  String name = '';
  String? failure;
  Completer<VideoRecovery>? _recovery;
  void recover(VideoRecovery choice) {
    final pending = _recovery;
    if (pending != null && !pending.isCompleted) pending.complete(choice);
  }

  void cancel() {
    _canceled = true;
    recover(VideoRecovery.cancel);
    notifyListeners();
  }

  Future<AttachmentDraft> prepare(AttachmentDraft draft) async {
    if (!_supported || !draft.mimeType.startsWith('video/')) {
      return draft;
    }
    if (active) {
      throw StateError('Another video is being prepared. Please wait.');
    }
    active = true;
    _canceled = false;
    progress = 0;
    name = draft.name;
    failure = null;
    notifyListeners();
    try {
      while (true) {
        if (_canceled) throw StateError('Video preparation canceled.');
        try {
          final result = await _optimizer(
            draft,
            progress: (v) {
              progress = v;
              notifyListeners();
            },
            canceled: () => _canceled,
          );
          if (_canceled) throw StateError('Video preparation canceled.');
          return result;
        } catch (error) {
          if (_canceled) rethrow;
          failure = error.toString().replaceFirst('Bad state: ', '');
          _recovery = Completer<VideoRecovery>();
          notifyListeners();
          final choice = await _recovery!.future;
          _recovery = null;
          failure = null;
          if (choice == VideoRecovery.cancel) {
            throw StateError(
              'Video preparation canceled. Your draft was kept.',
            );
          }
          if (choice == VideoRecovery.original) {
            // Only an explicit choice may bypass compression. Upload size and
            // Matrix encryption checks still run in the normal send path.
            final original = await VideoPreparation.probe(draft);
            if (_canceled) throw StateError('Video preparation canceled.');
            return original;
          }
          progress = 0;
          notifyListeners();
        }
      }
    } finally {
      active = false;
      failure = null;
      _recovery = null;
      notifyListeners();
    }
  }
}
