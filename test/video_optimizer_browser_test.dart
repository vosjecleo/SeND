@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/video_preparation.dart';
import 'package:deltiecord/services/video_optimizer.dart';
import 'package:deltiecord/models/video_edit.dart';
import 'fixtures/video_leading_black.dart';

void main() {
  test(
    'web codec bridge preserves caption, spoiler, metadata and edited output',
    () async {
      final bytes = base64Decode(leadingBlackVideoBase64);
      final keys = [
        'sendWebVideoSupported',
        'sendWebVideoProcess',
        'sendWebVideoCancel',
      ];
      final old = [
        for (final key in keys) globalContext.getProperty<JSAny?>(key.toJS),
      ];
      addTearDown(() {
        for (var i = 0; i < keys.length; i++) {
          if (old[i] == null) {
            globalContext.delete(keys[i].toJS);
          } else {
            globalContext.setProperty(keys[i].toJS, old[i]);
          }
        }
      });
      Map? received;
      globalContext.setProperty(keys[0].toJS, (() => true).toJS);
      globalContext.setProperty(
        keys[1].toJS,
        ((JSUint8Array input, JSAny? options, JSFunction progress) {
          received = options.dartify() as Map;
          progress.callAsFunction(null, .5.toJS);
          return Future<JSObject>.value(
            {'bytes': bytes.toJS}.jsify() as JSObject,
          ).toJS;
        }).toJS,
      );
      globalContext.setProperty(keys[2].toJS, ((JSNumber _) {}).toJS);
      expect(videoOptimizationSupported, true);
      final result = await optimizeVideo(
        AttachmentDraft(
          bytes: bytes,
          name: 'source.mov',
          mimeType: 'video/quicktime',
          spoiler: true,
          caption: 'caption',
        ),
        progress: (_) {},
        canceled: () => false,
        edit: const VideoEditPlan(muted: true),
      );
      expect((received!['edit'] as Map)['muted'], true);
      expect(result.mimeType, 'video/mp4');
      expect(result.caption, 'caption');
      expect(result.spoiler, true);
      expect(result.videoPrepared, true);
      expect(result.videoWidth, 64);
      expect(result.videoHeight, 48);
      globalContext.setProperty(
        keys[1].toJS,
        ((JSUint8Array _, JSAny? _, JSFunction _) => Future<JSObject>.value(
          {'error': 'Unsupported audio codec. Choose Original.'}.jsify()
              as JSObject,
        ).toJS).toJS,
      );
      await expectLater(
        optimizeVideo(
          AttachmentDraft(
            bytes: bytes,
            name: 'clip.mp4',
            mimeType: 'video/mp4',
            spoiler: false,
          ),
          progress: (_) {},
          canceled: () => false,
          edit: const VideoEditPlan(muted: true),
        ),
        throwsStateError,
      );
    },
  );
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
