import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/media_compression.dart';
import 'package:deltiecord/services/image_preparation.dart';
import 'package:deltiecord/services/encoded_image_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'image quality resizes an opaque photo and preserves attachment metadata',
    () async {
      final pixels = image.Image(width: 1600, height: 800);
      for (var y = 0; y < pixels.height; y++) {
        for (var x = 0; x < pixels.width; x++) {
          pixels.setPixelRgb(
            x,
            y,
            (x * 7 + y * 3) % 256,
            (x * 13 + y) % 256,
            (x + y * 11) % 256,
          );
        }
      }
      final original = AttachmentDraft(
        bytes: Uint8List.fromList(image.encodeJpg(pixels, quality: 98)),
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        spoiler: true,
        caption: 'Keep caption',
      );
      final prepared = await prepareImage(
        original,
        ImageCompressionPreset.smaller,
      );
      final size = await readEncodedImageDimensions(prepared.bytes);
      expect(size!.width, 1280);
      expect(size.height, 640);
      expect(prepared.bytes.length, lessThan(original.bytes.length));
      expect(prepared.spoiler, true);
      expect(prepared.caption, 'Keep caption');
      expect(prepared.imagePrepared, true);
      expect(
        identical(
          (await prepareImage(prepared, ImageCompressionPreset.smaller)).bytes,
          prepared.bytes,
        ),
        true,
      );
    },
  );
  test(
    'animated images and original quality are never flattened or reencoded',
    () async {
      final bytes = Uint8List.fromList('GIF89a synthetic animation'.codeUnits);
      final gif = AttachmentDraft(
        bytes: bytes,
        name: 'a.gif',
        mimeType: 'image/gif',
        spoiler: false,
        gifSource: Uri.parse('https://static.klipy.com/a.gif'),
      );
      expect(
        identical(await prepareImage(gif, ImageCompressionPreset.smaller), gif),
        true,
      );
      final copied = gif.copyWith(spoiler: true, caption: 'caption');
      expect(copied.gifSource, gif.gifSource);
      expect(copied.bytes, bytes);
      expect(copied.spoiler, true);
    },
  );
  test(
    'compression defaults preserve existing image behavior and bounded video profiles',
    () {
      const prefs = AppPreferences();
      expect(prefs.imageCompression, ImageCompressionPreset.original);
      expect(prefs.shareUploadCategories, false);
      expect(prefs.videoCompression, VideoCompressionPreset.balanced);
      expect(VideoCompressionPreset.smaller.maximumBytes, 12 * 1024 * 1024);
      expect(VideoCompressionPreset.balanced.maximumBytes, 24 * 1024 * 1024);
      final changed = prefs.copyWith(
        videoCompression: VideoCompressionPreset.smaller,
        imageCompression: ImageCompressionPreset.smaller,
      );
      expect(
        changed.copyWith(fontScale: 1.1).videoCompression,
        VideoCompressionPreset.smaller,
      );
      expect(changed.imageCompression, ImageCompressionPreset.smaller);
    },
  );
}
