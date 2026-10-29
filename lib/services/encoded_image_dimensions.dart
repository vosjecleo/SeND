import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as image;

/// Reads encoded image dimensions without decoding a full frame.
///
/// Used for media geometry, editing and compression admission. The pixel bound
/// rejects oversized image headers before full-resolution decoding.
Future<({int width, int height})?> readEncodedImageDimensions(
  Uint8List bytes, {
  int maximumPixels = 40000000,
}) async {
  // Encoded ImageDescriptor.width/height throw UnsupportedError on web.
  // Read headers there, without decoding a full-resolution pixel buffer.
  if (kIsWeb) {
    try {
      final decoder = image.findDecoderForData(bytes);
      if (decoder is! image.JpegDecoder &&
          decoder is! image.PngDecoder &&
          decoder is! image.GifDecoder &&
          decoder is! image.WebPDecoder &&
          decoder is! image.BmpDecoder) {
        return null;
      }
      final info = decoder!.startDecode(bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width * info.height > maximumPixels) {
        return null;
      }
      return (width: info.width, height: info.height);
    } catch (_) {
      return null;
    }
  }
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    final height = descriptor.height;
    if (width <= 0 || height <= 0 || width * height > maximumPixels) {
      return null;
    }
    return (width: width, height: height);
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
