import 'package:deltiecord/ui/profile_image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as image;

void main() {
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
