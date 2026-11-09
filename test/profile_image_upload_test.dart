import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:deltiecord/services/profile_image_upload.dart';
import 'package:deltiecord/services/image_animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final role in ProfileImageRole.values) {
    test(
      '${role.name} is resized to its edge limit without distortion',
      () async {
        final source = image.Image(width: role.maximumEdge + 200, height: 200);
        final prepared = await prepareProfileImage(
          Uint8List.fromList(image.encodePng(source)),
          role,
        );
        final result = image.decodeImage(prepared.bytes)!;
        expect(result.width, role.maximumEdge);
        expect(
          result.height,
          closeTo(200 * role.maximumEdge / source.width, 1),
        );
        expect(prepared.mimeType, 'image/jpeg');
        expect(prepared.extension, 'jpg');
      },
    );
  }

  test(
    'small opaque images are not enlarged, alpha stays transparent',
    () async {
      final source = image.Image(width: 48, height: 24, numChannels: 4);
      image.fill(source, color: image.ColorRgba8(80, 90, 100, 40));
      final prepared = await prepareProfileImage(
        Uint8List.fromList(image.encodePng(source)),
        ProfileImageRole.avatar,
      );
      final result = image.decodeImage(prepared.bytes)!;
      expect((result.width, result.height), (48, 24));
      expect(result.getPixel(0, 0).a, 40);
      expect(prepared.mimeType, 'image/png');
    },
  );

  test(
    'animated avatars retain frames, timing, repeat and composited colours',
    () async {
      final first = image.Image(width: 600, height: 100)
        ..frameDuration = 100
        ..loopCount = 3;
      image.fill(first, color: image.ColorRgb8(255, 0, 0));
      final second = image.Image(width: 600, height: 100)..frameDuration = 200;
      image.fill(second, color: image.ColorRgb8(0, 0, 255));
      first.addFrame(second);
      final prepared = await prepareProfileImage(
        Uint8List.fromList(image.encodeGif(first, repeat: 3)),
        ProfileImageRole.avatar,
      );
      expect(hasAnimatedImageHeader(prepared.bytes), isTrue);
      expect(prepared.mimeType, 'image/png');
      final codec = await ui.instantiateImageCodec(prepared.bytes);
      try {
        expect(codec.frameCount, 2);
        expect(codec.repetitionCount, 3);
        for (var i = 0; i < 2; i++) {
          final frame = await codec.getNextFrame();
          try {
            expect(frame.image.width, 512);
            expect(frame.duration.inMilliseconds, i == 0 ? 100 : 200);
            final rgba = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(rgba!.getUint8(i == 0 ? 0 : 2), 255);
          } finally {
            frame.image.dispose();
          }
        }
      } finally {
        codec.dispose();
      }
    },
  );

  test('invalid asset data fails before upload', () async {
    await expectLater(
      prepareProfileImage(Uint8List(10), ProfileImageRole.avatar),
      throwsStateError,
    );
  });
}
