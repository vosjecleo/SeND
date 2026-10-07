import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/chat_models.dart';
import 'video_preparation_android.dart';

bool get videoOptimizationSupported =>
    Platform.isAndroid ||
    Platform.isLinux ||
    Platform.isWindows ||
    Platform.isMacOS;

Future<AttachmentDraft> probeVideo(AttachmentDraft draft) async {
  if (!draft.mimeType.startsWith('video/')) return draft;
  if (Platform.isAndroid) {
    return prepareAndroidVideo(
      draft,
      optimize: false,
      progress: (_) {},
      canceled: () => false,
    );
  }
  try {
    return await optimizeVideo(
      draft,
      progress: (_) {},
      canceled: () => false,
      optimize: false,
    );
  } catch (_) {
    // Metadata is best effort; missing local codecs must not block originals.
    return draft;
  }
}

const _maximumBytes = 24 * 1024 * 1024;

/// First-preview desktop adapter. FFmpeg/ffprobe are resolved from PATH; neither
/// credentials nor media leave this device. Never truncate to meet the budget.
Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
  bool optimize = true,
}) async {
  if (!videoOptimizationSupported || !draft.mimeType.startsWith('video/')) {
    return draft;
  }
  if (Platform.isAndroid) {
    return prepareAndroidVideo(
      draft,
      optimize: optimize,
      progress: progress,
      canceled: canceled,
    );
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
    final timeout = Timer(
      optimize ? const Duration(minutes: 10) : const Duration(seconds: 30),
      () {
        expired = true;
        active.kill();
      },
    );
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
    if (video == null || (optimize && (!duration.isFinite || duration <= 0))) {
      throw StateError(
        'Could not read this video’s duration. Choose original quality to send it unchanged.',
      );
    }
    if (optimize) {
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
    }
    final media = optimize ? output : input;
    final verified = optimize
        ? jsonDecode(
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
              as Map
        : metadata;
    final encoded = (verified['streams'] as List).whereType<Map>().firstWhere(
      (s) => s['codec_type'] == 'video',
    );
    final encodedDuration =
        double.tryParse(verified['format']?['duration']?.toString() ?? '') ??
        duration;
    final thumbnail = File('${directory.path}/thumbnail.jpg');
    try {
      await run('ffmpeg', [
        '-nostdin',
        '-hide_banner',
        '-loglevel',
        'error',
        '-protocol_whitelist',
        'file,pipe',
        '-i',
        media.path,
        '-frames:v',
        '1',
        '-vf',
        "scale=w='if(gte(dar,1),480,max(1,round(480*dar)))':h='if(gte(dar,1),max(1,round(480/dar)),480)',setsar=1",
        '-threads',
        '1',
        thumbnail.path,
      ]);
    } catch (_) {
      if (canceled()) rethrow;
      // A missing poster must not discard good dimensions or a usable video.
    }
    if (canceled()) throw StateError('Video preparation canceled.');
    final bytes = optimize ? await output.readAsBytes() : draft.bytes;
    final size = videoDisplaySize(encoded);
    progress(1);
    return AttachmentDraft(
      bytes: bytes,
      name: optimize
          ? '${draft.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.mp4'
          : draft.name,
      mimeType: optimize ? 'video/mp4' : draft.mimeType,
      spoiler: draft.spoiler,
      caption: draft.caption,
      durationMilliseconds: encodedDuration.isFinite && encodedDuration > 0
          ? (encodedDuration * 1000).round()
          : draft.durationMilliseconds,
      gifSource: draft.gifSource,
      videoWidth: size?.$1 ?? draft.videoWidth,
      videoHeight: size?.$2 ?? draft.videoHeight,
      videoThumbnail: await thumbnail.exists() && await thumbnail.length() > 0
          ? await thumbnail.readAsBytes()
          : draft.videoThumbnail,
    );
  } finally {
    cancellation?.cancel();
    process?.kill();
    // Only this freshly created, private task directory is removed.
    await directory.delete(recursive: true);
  }
}

/// Matrix w/h describe displayed pixels, not the encoded camera orientation.
(int, int)? videoDisplaySize(Map metadata) {
  final width = metadata['width'];
  final height = metadata['height'];
  if (width is! num || height is! num || width <= 0 || height <= 0) return null;
  final sar = '${metadata['sample_aspect_ratio']}'.split(':');
  final numerator = sar.length == 2 ? double.tryParse(sar[0]) : null;
  final denominator = sar.length == 2 ? double.tryParse(sar[1]) : null;
  final ratio =
      numerator != null &&
          denominator != null &&
          numerator > 0 &&
          denominator > 0
      ? numerator / denominator
      : 1.0;
  final displayedWidth = (width * ratio).round();
  final sideData = metadata['side_data_list'];
  final rotation =
      (sideData is List
          ? sideData
                .whereType<Map>()
                .map((item) => item['rotation'])
                .whereType<num>()
                .firstOrNull
          : null) ??
      num.tryParse(
        '${metadata['tags'] is Map ? metadata['tags']['rotate'] : ''}',
      ) ??
      0;
  return rotation.round().abs() % 180 == 90
      ? (height.round(), displayedWidth)
      : (displayedWidth, height.round());
}
