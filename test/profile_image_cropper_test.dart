import 'package:deltiecord/ui/profile_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> checkAnimation(
    Uint8List source, {
    required int left,
    required int top,
    required int width,
    required int height,
  }) async {
    final cropped = await cropAnimatedProfileImage((
      bytes: source,
      left: left,
      top: top,
      width: width,
      height: height,
      maximumWidth: width,
    ));
    final original = await ui.instantiateImageCodec(source);
    final output = await ui.instantiateImageCodec(cropped);
    try {
      expect(output.frameCount, original.frameCount);
      expect(output.repetitionCount, original.repetitionCount);
      for (var i = 0; i < original.frameCount; i++) {
        final a = await original.getNextFrame();
        final b = await output.getNextFrame();
        try {
          expect(b.duration, a.duration, reason: 'frame $i timing');
          expect((b.image.width, b.image.height), (width, height));
          final ap = (await a.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final bp = (await b.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final expected = Uint8List(width * height * 4);
          final actual = bp.buffer.asUint8List(
            bp.offsetInBytes,
            bp.lengthInBytes,
          );
          for (var y = 0; y < height; y++) {
            final start = ((y + top) * a.image.width + left) * 4;
            expected.setRange(
              y * width * 4,
              (y + 1) * width * 4,
              ap.buffer.asUint8List(ap.offsetInBytes + start, width * 4),
            );
          }
          expect(
            actual,
            orderedEquals(expected),
            reason: 'frame $i colours/transparency',
          );
        } finally {
          a.image.dispose();
          b.image.dispose();
        }
      }
    } finally {
      original.dispose();
      output.dispose();
    }
  }

  test(
    'animated crop preserves changing palettes, timing and looping',
    () async {
      final gif = image.GifEncoder(repeat: 2);
      for (var frame = 0; frame < 3; frame++) {
        final pixels = image.Image(width: 12, height: 8, numChannels: 4);
        image.fillRect(
          pixels,
          x1: frame,
          y1: 1,
          x2: 9,
          y2: 6,
          color: image.ColorRgba8(255, frame * 60, 180 - frame * 30, 255),
        );
        gif.addFrame(pixels, duration: 5 + frame * 5);
      }
      await checkAnimation(
        gif.finish()!,
        left: 1,
        top: 2,
        width: 10,
        height: 4,
      );
    },
  );

  test('private GIF sample retains every cropped pixel', () async {
    final source = await File(
      Platform.environment['SEND_GIF_CROP_SAMPLE']!,
    ).readAsBytes();
    await checkAnimation(source, left: 0, top: 83, width: 250, height: 83);
  }, skip: !Platform.environment.containsKey('SEND_GIF_CROP_SAMPLE'));

  test('saved crop uses the exact selected region and preserves aspect', () {
    final source = image.Image(width: 400, height: 200);
    image.fill(source, color: image.ColorRgb8(0, 0, 255));
    image.fillRect(
      source,
      x1: 200,
      y1: 0,
      x2: 399,
      y2: 199,
      color: image.ColorRgb8(255, 0, 0),
    );
    final region = calculateProfileCropRegion(
      imageWidth: 400,
      imageHeight: 200,
      aspectRatio: 1,
      zoom: 1,
      horizontalPosition: 1,
      verticalPosition: 0.5,
    );
    final output = image.decodePng(
      cropProfileImage((
        bytes: Uint8List.fromList(image.encodePng(source)),
        left: region.left.round(),
        top: region.top.round(),
        width: region.width.round(),
        height: region.height.round(),
        maximumWidth: 100,
      )),
    )!;
    expect(output.width, 100);
    expect(output.height, 100);
    expect(output.getPixel(50, 50).r, 255);
    expect(output.getPixel(50, 50).b, 0);
  });
  test('banner crop region keeps the requested aspect and position', () {
    final region = calculateProfileCropRegion(
      imageWidth: 4000,
      imageHeight: 2000,
      aspectRatio: 3,
      zoom: 2,
      horizontalPosition: 1,
      verticalPosition: 0.5,
    );

    expect(region.width / region.height, closeTo(3, 0.0001));
    expect(region.left + region.width, closeTo(4000, 0.001));
    expect(region.top, greaterThan(0));
  });

  test('avatar crop starts with the largest centered square', () {
    final region = calculateProfileCropRegion(
      imageWidth: 2400,
      imageHeight: 1600,
      aspectRatio: 1,
      zoom: 1,
      horizontalPosition: 0.5,
      verticalPosition: 0.5,
    );

    expect(region.width, 1600);
    expect(region.height, 1600);
    expect(region.left, 400);
    expect(region.top, 0);
  });
}
