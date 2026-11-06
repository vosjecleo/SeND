import 'dart:typed_data';
import 'package:deltiecord/services/encoded_image_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pixel limit is checked before a full-sized image decode', () async {
    final bytes = image.encodePng(image.Image(width: 64, height: 64));
    expect(await readEncodedImageDimensions(bytes, maximumPixels: 4096), (
      width: 64,
      height: 64,
    ));
    expect(
      await readEncodedImageDimensions(bytes, maximumPixels: 4095),
      isNull,
    );
  });
  test('animation budget accounts for all frames on native and web', () async {
    final encoder = image.GifEncoder();
    encoder.addFrame(
      image.Image(width: 16, height: 16)..setPixelRgb(0, 0, 255, 0, 0),
    );
    encoder.addFrame(
      image.Image(width: 16, height: 16)..setPixelRgb(0, 0, 0, 255, 0),
    );
    final bytes = Uint8List.fromList(encoder.finish()!);
    expect(await readEncodedImageDimensions(bytes, maximumFramePixels: 512), (
      width: 16,
      height: 16,
    ));
    expect(
      await readEncodedImageDimensions(bytes, maximumFramePixels: 511),
      isNull,
    );
  });
}
