import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../models/video_edit.dart';

const _channel = MethodChannel('net.deltie.deltiecord/video_prepare');

Future<AttachmentDraft> prepareAndroidVideo(
  AttachmentDraft draft, {
  required bool optimize,
  VideoCompressionPreset preset = VideoCompressionPreset.balanced,
  VideoEditPlan? edit,
  required void Function(double) progress,
  required bool Function() canceled,
  Future<Directory> Function() cacheDirectory = getTemporaryDirectory,
}) async {
  // Flutter's Android systemTemp is code_cache, while our native bridge
  // deliberately accepts only Context.cacheDir. path_provider resolves that
  // exact private cache directory; do not broaden the native file allowlist.
  final cache = await cacheDirectory();
  final directory = await cache.createTemp('send-video-');
  Timer? polling;
  var pollingBusy = false;
  try {
    final input = File('${directory.path}/input');
    final output = File('${directory.path}/output.mp4');
    await input.writeAsBytes(draft.bytes);
    var metadata = await _channel.invokeMapMethod<String, Object?>('probe', {
      'input': input.path,
    });
    if (metadata == null) {
      if (edit?.hasChanges == true) {
        throw StateError('Could not read this video for editing.');
      }
      return draft;
    }
    if (canceled()) throw StateError('Video preparation canceled.');
    var bytes = draft.bytes;
    if (optimize || edit?.hasChanges == true) {
      final duration = (metadata['duration'] as num?)?.toDouble() ?? 0;
      if (duration <= 0) {
        throw StateError(
          'Could not read video duration. Choose original quality to send it unchanged.',
        );
      }
      final clipDuration =
          edit?.durationMs(duration.round()) ?? duration.round();
      final bitrate = (preset.targetBytes * 8 / (clipDuration / 1000) - 192000)
          .floor();
      if (optimize && bitrate < 250000) {
        throw StateError(
          'This clip is too long for the optimized size limit. Trim it or choose original quality.',
        );
      }
      polling = Timer.periodic(const Duration(milliseconds: 300), (_) async {
        if (pollingBusy) return;
        pollingBusy = true;
        try {
          if (canceled()) {
            await _channel.invokeMethod<void>('cancel');
          } else {
            final value = await _channel.invokeMethod<int>('progress') ?? 0;
            progress((value / 100).clamp(0, .99));
          }
        } catch (_) {
        } finally {
          pollingBusy = false;
        }
      });
      await _channel
          .invokeMethod<void>('optimize', {
            'input': input.path,
            'output': output.path,
            'width': metadata['width'],
            'height': metadata['height'],
            'bitrate': optimize
                ? bitrate.clamp(250000, preset.maximumBitrate)
                : 8000000,
            if (edit != null) 'edit': edit.toMap(),
            'resize': optimize,
          })
          .timeout(const Duration(minutes: 10));
      if (canceled()) throw StateError('Video preparation canceled.');
      if (optimize && await output.length() > preset.maximumBytes) {
        throw StateError(
          'The optimized clip is still too large. Trim it or choose original quality.',
        );
      }
      bytes = await output.readAsBytes();
      metadata =
          await _channel.invokeMapMethod<String, Object?>('probe', {
            'input': output.path,
          }) ??
          metadata;
      progress(1);
    }
    return AttachmentDraft(
      bytes: bytes,
      name: optimize || edit?.hasChanges == true
          ? '${draft.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.mp4'
          : draft.name,
      mimeType: optimize || edit?.hasChanges == true
          ? 'video/mp4'
          : draft.mimeType,
      spoiler: draft.spoiler,
      caption: draft.caption,
      gifSource: draft.gifSource,
      videoWidth: metadata['width'] as int?,
      videoHeight: metadata['height'] as int?,
      durationMilliseconds: (metadata['duration'] as num?)?.toInt(),
      videoThumbnail: metadata['thumbnail'] as Uint8List?,
    );
  } catch (_) {
    if (!optimize && edit?.hasChanges != true) {
      return draft; // Original-quality upload must remain possible.
    }
    rethrow;
  } finally {
    polling?.cancel();
    if (optimize || edit?.hasChanges == true) {
      try {
        await _channel.invokeMethod<void>('cancel');
      } catch (_) {}
    }
    await directory.delete(recursive: true);
  }
}
