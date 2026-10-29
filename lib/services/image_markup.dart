import 'dart:typed_data';
import 'dart:math' as math;
import '../models/markup_stroke.dart';
import 'dart:ui' as ui;
import 'package:image/image.dart' as image;
import 'encoded_image_dimensions.dart';

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
  final size = await readEncodedImageDimensions(
    bytes,
    maximumPixels: 100000000,
  );
  if (size == null) {
    throw const FormatException('This image cannot be edited here.');
  }
  final scale = 4096 / (size.width > size.height ? size.width : size.height);
  final width = (size.width * (scale < 1 ? scale : 1)).round(),
      height = (size.height * (scale < 1 ? scale : 1)).round();
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
        final quarterTurns = turns % 4;
        final rotatedWidth = quarterTurns.isOdd
            ? frame.image.height
            : frame.image.width;
        final rotatedHeight = quarterTurns.isOdd
            ? frame.image.width
            : frame.image.height;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.save();
        switch (quarterTurns) {
          case 1:
            canvas.translate(frame.image.height.toDouble(), 0);
            canvas.rotate(math.pi / 2);
          case 2:
            canvas.translate(
              frame.image.width.toDouble(),
              frame.image.height.toDouble(),
            );
            canvas.rotate(math.pi);
          case 3:
            canvas.translate(0, frame.image.width.toDouble());
            canvas.rotate(-math.pi / 2);
        }
        canvas.drawImage(frame.image, ui.Offset.zero, ui.Paint());
        canvas.restore();
        paintMarkupStrokes(
          canvas,
          ui.Size(rotatedWidth.toDouble(), rotatedHeight.toDouble()),
          [
            for (final stroke in strokes)
              MarkupStroke(stroke['color'] as int, stroke['width'] as double, [
                for (final p in (stroke['points'] as List).cast<List<double>>())
                  ui.Offset(p[0], p[1]),
              ]),
          ],
        );
        final picture = recorder.endRecording();
        final composed = await picture.toImage(rotatedWidth, rotatedHeight);
        picture.dispose();
        late image.Image output;
        try {
          final pixels = await composed.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          if (pixels == null) {
            throw const FormatException('Could not read image pixels.');
          }
          output = image.Image.fromBytes(
            width: rotatedWidth,
            height: rotatedHeight,
            bytes: pixels.buffer,
            bytesOffset: pixels.offsetInBytes,
            numChannels: 4,
          );
        } finally {
          composed.dispose();
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
