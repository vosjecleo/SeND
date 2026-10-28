import 'dart:io';
import 'dart:convert';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/video_edit.dart';
import 'package:deltiecord/services/video_optimizer_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/ffmpeg_tools.dart';

void main() {
  test(
    'video export trims, rotates, crops and removes audio from actual output',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'send-edit-test-',
      );
      try {
        final input = File('${directory.path}/input.mp4');
        final created = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=96x64:rate=10',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=44100',
          '-t',
          '2',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          '-c:a',
          'aac',
          input.path,
        ]);
        expect(created.exitCode, 0, reason: created.stderr.toString());
        final result = await optimizeVideo(
          AttachmentDraft(
            bytes: await input.readAsBytes(),
            name: 'a.mp4',
            mimeType: 'video/mp4',
            spoiler: true,
            caption: 'caption',
          ),
          optimize: false,
          edit: const VideoEditPlan(
            startMs: 500,
            endMs: 1500,
            turns: 1,
            left: .25,
            width: .5,
            muted: true,
          ),
          progress: (_) {},
          canceled: () => false,
        );
        expect(result.videoWidth, 32);
        expect(result.videoHeight, 96);
        expect(result.durationMilliseconds, inInclusiveRange(900, 1100));
        expect(result.caption, 'caption');
        expect(result.spoiler, true);
        final output = File('${directory.path}/output.mp4');
        await output.writeAsBytes(result.bytes);
        final info = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_streams',
          '-of',
          'json',
          output.path,
        ]);
        final streams = (jsonDecode(info.stdout as String)['streams'] as List)
            .cast<Map>();
        expect(streams.any((s) => s['codec_type'] == 'audio'), false);
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: !ffmpegToolsAvailable(),
  );
  test('invalid edit bounds never export an untrimmed original', () {
    expect(
      () => const VideoEditPlan(startMs: 2000).durationMs(1000),
      throwsFormatException,
    );
    expect(
      () => const VideoEditPlan(width: 2).durationMs(1000),
      throwsFormatException,
    );
  });
}
