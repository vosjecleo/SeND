import 'package:flutter/foundation.dart';
import '../models/chat_models.dart';
import 'video_optimizer.dart';

class VideoPreparation extends ChangeNotifier {
  static final instance = VideoPreparation();
  bool active = false;
  bool _canceled = false;
  double progress = 0;
  String name = '';
  void cancel() {
    _canceled = true;
    notifyListeners();
  }

  Future<AttachmentDraft> prepare(AttachmentDraft draft) async {
    if (!videoOptimizationSupported || !draft.mimeType.startsWith('video/')) {
      return draft;
    }
    if (active) {
      throw StateError('Another video is being prepared. Please wait.');
    }
    active = true;
    _canceled = false;
    progress = 0;
    name = draft.name;
    notifyListeners();
    try {
      return await optimizeVideo(
        draft,
        progress: (v) {
          progress = v;
          notifyListeners();
        },
        canceled: () => _canceled,
      );
    } finally {
      active = false;
      notifyListeners();
    }
  }
}
