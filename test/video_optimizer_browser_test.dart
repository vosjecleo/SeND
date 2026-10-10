@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/video_preparation.dart';
import 'package:deltiecord/services/video_optimizer.dart';
import 'fixtures/video_leading_black.dart';

void main() {
  test(
    'browser upload keeps its original and publishes dimensions and a visible poster',
    () async {
      final bytes = base64Decode(leadingBlackVideoBase64);
      final draft = AttachmentDraft(
        bytes: bytes,
        name: 'clip.mp4',
        mimeType: 'video/mp4',
        spoiler: true,
        caption: 'Caption',
      );
      final preparation = VideoPreparation(supported: false);
      final result = await preparation.prepare(draft);
      preparation.dispose();
      expect(videoOptimizationSupported, isFalse);
      expect(result.bytes, same(bytes));
      expect(result.videoWidth, 64);
      expect(result.videoHeight, 48);
      expect(result.durationMilliseconds, closeTo(30000, 100));
      expect(result.spoiler, isTrue);
      expect(result.caption, 'Caption');
      expect(result.videoThumbnail, isNotEmpty);
      final poster = image.decodeJpg(result.videoThumbnail!)!;
      final pixel = poster.getPixel(poster.width ~/ 2, poster.height ~/ 2);
      expect(pixel.r, greaterThan(200));
      expect(pixel.g, lessThan(30));
    },
  );
}
