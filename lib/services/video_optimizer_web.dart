import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../models/chat_models.dart';

bool get videoOptimizationSupported => false;

/// Read local metadata and a small poster without re-encoding the upload.
/// The temporary Blob never sends the video to another service.
Future<AttachmentDraft> probeVideo(AttachmentDraft draft) async {
  if (!draft.mimeType.startsWith('video/') || draft.bytes.isEmpty) return draft;
  final video = web.HTMLVideoElement()
    ..preload = 'auto'
    ..muted = true
    ..playsInline = true;
  final url = web.URL.createObjectURL(
    web.Blob(
      [draft.bytes.toJS].toJS,
      web.BlobPropertyBag(type: draft.mimeType),
    ),
  );
  var width = draft.videoWidth, height = draft.videoHeight;
  var duration = draft.durationMilliseconds;
  var poster = draft.videoThumbnail;
  try {
    final metadata = _waitForVideoEvent(video, 'loadedmetadata');
    video.src = url;
    video.load();
    await metadata;
    if (video.videoWidth > 0 && video.videoHeight > 0) {
      width = video.videoWidth;
      height = video.videoHeight;
    }
    if (video.duration.isFinite && video.duration > 0) {
      duration = (video.duration * 1000).round();
    }
    if (width != null && height != null) {
      final time = min(10.0, max(0.0, video.duration / 10));
      if (time.isFinite && time > 0) {
        final seek = _waitForVideoEvent(video, 'seeked');
        video.currentTime = time;
        await seek;
      } else if (video.readyState < 2) {
        await _waitForVideoEvent(video, 'loadeddata');
      }
      final scale = min(1.0, 480 / max(width, height));
      final canvas = web.HTMLCanvasElement()
        ..width = max(1, (width * scale).round())
        ..height = max(1, (height * scale).round());
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context != null) {
        context.drawImage(
          video,
          0,
          0,
          canvas.width.toDouble(),
          canvas.height.toDouble(),
        );
        final result = Completer<web.Blob?>();
        canvas.toBlob(
          ((web.Blob? blob) => result.complete(blob)).toJS,
          'image/jpeg',
          .75.toJS,
        );
        final blob = await result.future.timeout(const Duration(seconds: 5));
        if (blob != null && blob.size <= 1024 * 1024) {
          poster = (await blob.arrayBuffer().toDart).toDart.asUint8List();
        }
      }
    }
  } catch (_) {
    // A browser may lack this codec. Keep any metadata already obtained.
  } finally {
    video.pause();
    video.removeAttribute('src');
    video.load();
    web.URL.revokeObjectURL(url);
  }
  return AttachmentDraft(
    bytes: draft.bytes,
    name: draft.name,
    mimeType: draft.mimeType,
    spoiler: draft.spoiler,
    caption: draft.caption,
    gifSource: draft.gifSource,
    durationMilliseconds: duration,
    videoWidth: width,
    videoHeight: height,
    videoThumbnail: poster,
  );
}

Future<void> _waitForVideoEvent(
  web.HTMLVideoElement video,
  String event,
) async {
  final result = Completer<void>();
  final loaded = ((web.Event _) {
    if (!result.isCompleted) result.complete();
  }).toJS;
  final failed = ((web.Event _) {
    if (!result.isCompleted) {
      result.completeError(StateError('Could not read video metadata.'));
    }
  }).toJS;
  video.addEventListener(event, loaded);
  video.addEventListener('error', failed);
  try {
    await result.future.timeout(const Duration(seconds: 8));
  } finally {
    video.removeEventListener(event, loaded);
    video.removeEventListener('error', failed);
  }
}

Future<AttachmentDraft> optimizeVideo(
  AttachmentDraft draft, {
  required void Function(double) progress,
  required bool Function() canceled,
}) => probeVideo(draft);
