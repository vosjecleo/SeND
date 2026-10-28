import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:image/image.dart' as image;

/// Use Flutter's compositor for indexed GIFs, preserving palette/transparency.
/// Only one decoded frame is retained; exported animations stay animated PNGs.
Future<Uint8List> renderMarkedImage({
  required Uint8List bytes,
  required int turns,
  required List<double> crop,
  required List<Map<String, Object?>> strokes,
  bool jpeg = false,
  bool Function()? canceled,
}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final scale =
      4096 /
      (descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height);
  final width = (descriptor.width * (scale < 1 ? scale : 1)).round(),
      height = (descriptor.height * (scale < 1 ? scale : 1)).round();
  descriptor.dispose();
  buffer.dispose();
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: width,
    targetHeight: height,
    allowUpscaling: false,
  );
  try {
    if (codec.frameCount > 1500 ||
        width * height * codec.frameCount > 150000000) {
      throw const FormatException('This image is too large to edit.');
    }
    final encoder = image.PngEncoder(level: 6)
      ..repeat = codec.repetitionCount < 0 ? 0 : codec.repetitionCount + 1
      ..start(codec.frameCount);
    for (var i = 0; i < codec.frameCount; i++) {
      if (canceled?.call() == true) {
        throw StateError('Image editing cancelled.');
      }
      final frame = await codec.getNextFrame();
      try {
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (pixels == null) {
          throw const FormatException('Could not read image pixels.');
        }
        var output = image.Image.fromBytes(
          width: frame.image.width,
          height: frame.image.height,
          bytes: pixels.buffer,
          bytesOffset: pixels.offsetInBytes,
          numChannels: 4,
        );
        if (turns % 4 != 0) {
          output = image.copyRotate(output, angle: (turns % 4) * 90);
        }
        for (final stroke in strokes) {
          final argb = stroke['color'] as int;
          final color = image.ColorRgba8(
            (argb >> 16) & 255,
            (argb >> 8) & 255,
            argb & 255,
            (argb >> 24) & 255,
          );
          final width =
              ((stroke['width'] as double) *
                      (output.width < output.height
                          ? output.width
                          : output.height))
                  .round()
                  .clamp(1, 500);
          final points = (stroke['points'] as List).cast<List<double>>();
          for (var p = 0; p < points.length; p++) {
            final a = points[p == 0 ? 0 : p - 1], b = points[p];
            image.drawLine(
              output,
              x1: (a[0] * (output.width - 1)).round(),
              y1: (a[1] * (output.height - 1)).round(),
              x2: (b[0] * (output.width - 1)).round(),
              y2: (b[1] * (output.height - 1)).round(),
              color: color,
              thickness: width,
              antialias: true,
            );
          }
        }
        final left = (crop[0] * output.width).round().clamp(
              0,
              output.width - 1,
            ),
            top = (crop[1] * output.height).round().clamp(0, output.height - 1);
        output = image.copyCrop(
          output,
          x: left,
          y: top,
          width: (crop[2] * output.width).round().clamp(1, output.width - left),
          height: (crop[3] * output.height).round().clamp(
            1,
            output.height - top,
          ),
        )..frameDuration = frame.duration.inMilliseconds;
        if (jpeg && codec.frameCount == 1) {
          return Uint8List.fromList(image.encodeJpg(output, quality: 95));
        }
        encoder.addFrame(output);
      } finally {
        frame.image.dispose();
      }
      await Future<void>.delayed(Duration.zero);
    }
    return encoder.finish()!;
  } finally {
    codec.dispose();
  }
}
