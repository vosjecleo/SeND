import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/chat_models.dart';

bool get videoOptimizationSupported =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;
const _maximumBytes = 24 * 1024 * 1024;

/// First-preview desktop adapter. FFmpeg/ffprobe are resolved from PATH; neither
/// credentials nor media leave this device. Never truncate to meet the budget.
Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
}) async {
  if (!videoOptimizationSupported || !draft.mimeType.startsWith('video/')) {
    return draft;
  }
  final directory = await Directory.systemTemp.createTemp('deltiecord-video-');
  Process? process;
  Timer? cancellation;
  Future<String> run(
    String executable,
    List<String> args, {
    bool encoding = false,
    double duration = 1,
  }) async {
    if (canceled()) throw StateError('Video preparation canceled.');
    try {
      process = await Process.start(executable, args);
    } on ProcessException {
      throw StateError(
        'Video optimization requires FFmpeg and ffprobe. Install them or disable video optimization in Audio & video settings to send the original.',
      );
    }
    final active = process!;
    var expired = false;
    final timeout = Timer(const Duration(minutes: 10), () {
      expired = true;
      active.kill();
    });
    cancellation = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (canceled()) active.kill();
    });
    final errors = active.stderr.drain<void>();
    final output = StringBuffer();
    try {
      await for (final line
          in active.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (encoding && line.startsWith('out_time_us=')) {
          final us = double.tryParse(line.substring(12));
          if (us != null) progress((us / 1000000 / duration).clamp(0, .99));
        } else if (!encoding && output.length < 1024 * 1024) {
          output.writeln(line);
        }
      }
      final exit = await active.exitCode;
      await errors;
      if (canceled()) throw StateError('Video preparation canceled.');
      if (expired || exit != 0) {
        throw StateError(
          'Video optimization failed. The original was not sent; you can retry or choose original quality in Audio & video settings.',
        );
      }
      return output.toString();
    } finally {
      timeout.cancel();
      cancellation?.cancel();
      process = null;
    }
  }

  try {
    final input = File('${directory.path}/input');
    final output = File('${directory.path}/optimized.mp4');
    await input.writeAsBytes(draft.bytes, flush: true);
    final raw = await run('ffprobe', [
      '-v',
      'error',
      '-protocol_whitelist',
      'file,pipe',
      '-show_format',
      '-show_streams',
      '-of',
      'json',
      input.path,
    ]);
    final metadata = jsonDecode(raw) as Map;
    final streams = (metadata['streams'] as List).whereType<Map>();
    final video = streams.where((s) => s['codec_type'] == 'video').firstOrNull;
    final duration =
        double.tryParse(metadata['format']?['duration']?.toString() ?? '') ?? 0;
    if (video == null || !duration.isFinite || duration <= 0) {
      throw StateError(
        'Could not read this video’s duration. Choose original quality to send it unchanged.',
      );
    }
    final audio = streams.any((s) => s['codec_type'] == 'audio');
    // Reserve muxing/bitrate variance headroom below the web viewer's 25 MiB
    // verified-download limit. Do not force unusable quality on long clips.
    final budget = (20 * 1024 * 1024 * 8 / duration - (audio ? 128000 : 0))
        .floor();
    if (budget < 250000) {
      throw StateError(
        'This video is too long for the optimized 24 MiB limit. Trim it or select original quality in Audio & video settings.',
      );
    }
    final bitrate = budget.clamp(250000, 4000000);
    await run(
      'ffmpeg',
      [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-protocol_whitelist',
        'file,pipe',
        '-i',
        input.path,
        '-map',
        '0:v:0',
        '-map',
        '0:a:0?',
        '-map_metadata',
        '-1',
        '-map_chapters',
        '-1',
        '-vf',
        "scale=w='if(gte(iw,ih),min(iw,1920),min(iw,1080))':h='if(gte(iw,ih),min(ih,1080),min(ih,1920))':force_original_aspect_ratio=decrease:force_divisible_by=2,fps=30",
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-threads',
        '2',
        '-pix_fmt',
        'yuv420p',
        '-b:v',
        '$bitrate',
        '-maxrate',
        '$bitrate',
        '-bufsize',
        '${bitrate * 2}',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-ac',
        '2',
        '-movflags',
        '+faststart',
        '-progress',
        'pipe:1',
        output.path,
      ],
      encoding: true,
      duration: duration,
    );
    if (canceled()) throw StateError('Video preparation canceled.');
    if (await output.length() > _maximumBytes) {
      throw StateError(
        'The optimized video still exceeds 24 MiB. The original was not sent; choose original quality or trim the clip.',
      );
    }
    final verified =
        jsonDecode(
              await run('ffprobe', [
                '-v',
                'error',
                '-protocol_whitelist',
                'file,pipe',
                '-show_streams',
                '-show_format',
                '-of',
                'json',
                output.path,
              ]),
            )
            as Map;
    final encoded = (verified['streams'] as List).whereType<Map>().firstWhere(
      (s) => s['codec_type'] == 'video',
    );
    final encodedDuration =
        double.tryParse(verified['format']?['duration']?.toString() ?? '') ??
        duration;
    final thumbnail = File('${directory.path}/thumbnail.jpg');
    await run('ffmpeg', [
      '-nostdin',
      '-hide_banner',
      '-loglevel',
      'error',
      '-protocol_whitelist',
      'file,pipe',
      '-i',
      output.path,
      '-frames:v',
      '1',
      '-vf',
      'scale=480:480:force_original_aspect_ratio=decrease',
      '-threads',
      '1',
      thumbnail.path,
    ]);
    if (canceled()) throw StateError('Video preparation canceled.');
    final bytes = await output.readAsBytes();
    progress(1);
    return AttachmentDraft(
      bytes: bytes,
      name: '${draft.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.mp4',
      mimeType: 'video/mp4',
      spoiler: draft.spoiler,
      caption: draft.caption,
      durationMilliseconds: (encodedDuration * 1000).round(),
      gifSource: draft.gifSource,
      videoWidth: encoded['width'] as int,
      videoHeight: encoded['height'] as int,
      videoThumbnail: await thumbnail.readAsBytes(),
    );
  } finally {
    cancellation?.cancel();
    process?.kill();
    // Only this freshly created, private task directory is removed.
    await directory.delete(recursive: true);
  }
}
