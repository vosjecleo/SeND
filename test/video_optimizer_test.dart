import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/video_optimizer_native.dart';

bool get hasFfmpeg {
  try {
    return Process.runSync('ffmpeg', ['-version']).exitCode == 0 &&
        Process.runSync('ffprobe', ['-version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test(
    'desktop optimization preserves aspect, caption and spoiler and creates a thumbnail',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'deltiecord-optimizer-test-',
      );
      try {
        final source = '${temp.path}/portrait.mp4';
        final generated = await Process.run('ffmpeg', [
          '-nostdin',
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=blue:s=360x640:d=1',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          source,
        ]);
        expect(generated.exitCode, 0, reason: generated.stderr.toString());
        final draft = AttachmentDraft(
          bytes: await File(source).readAsBytes(),
          name: 'portrait.mp4',
          mimeType: 'video/mp4',
          spoiler: true,
          caption: 'Caption',
        );
        final progress = <double>[];
        final original = await probeVideo(draft);
        expect(original.bytes, draft.bytes);
        expect(original.name, draft.name);
        expect(original.videoWidth, 360);
        expect(original.videoHeight, 640);
        expect(original.videoThumbnail, isNotEmpty);
        final result = await optimizeVideo(
          draft,
          progress: progress.add,
          canceled: () => false,
        );
        expect(result.mimeType, 'video/mp4');
        expect(result.videoWidth, 360);
        expect(result.videoHeight, 640);
        expect(result.videoThumbnail, isNotEmpty);
        expect(result.durationMilliseconds, closeTo(1000, 100));
        expect(result.caption, draft.caption);
        expect(result.spoiler, isTrue);
        expect(result.bytes.length, lessThan(24 * 1024 * 1024));
        expect(progress.last, 1);
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux || !hasFfmpeg,
  );
  test('cancel never silently sends original video', () async {
    final draft = AttachmentDraft(
      bytes: Uint8List(0),
      name: 'video.mp4',
      mimeType: 'video/mp4',
      spoiler: false,
    );
    await expectLater(
      optimizeVideo(draft, progress: (_) {}, canceled: () => true),
      throwsStateError,
    );
  }, skip: !Platform.isLinux);
  test('display dimensions respect camera rotation and non-square pixels', () {
    expect(
      videoDisplaySize({
        'width': 1920,
        'height': 1080,
        'side_data_list': [
          {'rotation': -90},
        ],
      }),
      (1080, 1920),
    );
    expect(
      videoDisplaySize({
        'width': 720,
        'height': 576,
        'sample_aspect_ratio': '16:15',
      }),
      (768, 576),
    );
    expect(videoDisplaySize({'width': 0, 'height': 576}), isNull);
  });
}
