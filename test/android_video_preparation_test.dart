import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/video_preparation_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.deltie.deltiecord/video_prepare');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final draft = AttachmentDraft(
    bytes: Uint8List.fromList([1, 2, 3]),
    name: 'camera.mov',
    mimeType: 'video/quicktime',
    spoiler: true,
    caption: 'caption',
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Android preparation retains rotated dimensions and message metadata',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'probe') {
          return <String, Object>{
            'width': 720,
            'height': 1280,
            'duration': 5000,
            'thumbnail': Uint8List.fromList([4, 5]),
          };
        }
        if (call.method == 'optimize') {
          expect(call.arguments['width'], 720);
          expect(call.arguments['height'], 1280);
          await File(
            call.arguments['output'] as String,
          ).writeAsBytes([6, 7, 8]);
        }
        return null;
      });
      final result = await prepareAndroidVideo(
        draft,
        optimize: true,
        progress: (_) {},
        canceled: () => false,
      );
      expect(result.name, 'camera.mp4');
      expect(result.bytes, [6, 7, 8]);
      expect(result.videoWidth, 720);
      expect(result.videoHeight, 1280);
      expect(result.videoThumbnail, [4, 5]);
      expect(result.caption, 'caption');
      expect(result.spoiler, true);
    },
  );

  test('failed optimization never silently sends the original', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'probe') {
        return {'width': 720, 'height': 1280, 'duration': 5000};
      }
      if (call.method == 'optimize') throw PlatformException(code: 'encode');
      return null;
    });
    await expectLater(
      prepareAndroidVideo(
        draft,
        optimize: true,
        progress: (_) {},
        canceled: () => false,
      ),
      throwsA(isA<PlatformException>()),
    );
  });

  test('original quality still probes metadata and does not encode', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'probe');
      return {'width': 1920, 'height': 1080, 'duration': 5000};
    });
    final result = await prepareAndroidVideo(
      draft,
      optimize: false,
      progress: (_) {},
      canceled: () => false,
    );
    expect(result.bytes, draft.bytes);
    expect(result.videoWidth, 1920);
    expect(result.videoHeight, 1080);
    expect(result.mimeType, 'video/quicktime');
  });
}
