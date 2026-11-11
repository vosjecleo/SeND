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
    'encoded dimensions work without a pixel decode and enforce limits',
    () async {
      final pixels = image.Image(width: 48, height: 24);
      for (final bytes in [
        image.encodePng(pixels),
        image.encodeJpg(pixels),
        image.encodeGif(pixels),
        image.encodeBmp(pixels),
      ]) {
        final encoded = Uint8List.fromList(bytes);
        expect(await readEncodedImageDimensions(encoded), (
          width: 48,
          height: 24,
        ));
        expect(
          await readEncodedImageDimensions(encoded, maximumPixels: 1000),
          isNull,
        );
      }
      expect(await readEncodedImageDimensions(Uint8List(0)), isNull);
    },
  );
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
      final frames = image.Image(width: 2, height: 2)..frameDuration = 80;
      frames.addFrame(image.Image(width: 2, height: 2)..frameDuration = 80);
      final bytes = Uint8List.fromList(image.encodeGif(frames));
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
    'edited oversized images cannot bypass Balanced resolution limits',
    () async {
      final draft = AttachmentDraft(
        bytes: Uint8List.fromList(
          image.encodePng(image.Image(width: 2100, height: 10)),
        ),
        name: 'edited.png',
        mimeType: 'image/png',
        spoiler: false,
        imagePrepared: true,
      );
      final prepared = await prepareImage(
        draft,
        ImageCompressionPreset.balanced,
      );
      expect((await readEncodedImageDimensions(prepared.bytes))!.width, 2048);
      expect(
        identical(
          await prepareImage(draft, ImageCompressionPreset.original),
          draft,
        ),
        isTrue,
      );
    },
  );
  test(
    'compression defaults use Balanced images and bounded Balanced videos',
    () {
      const prefs = AppPreferences();
      expect(prefs.imageCompression, ImageCompressionPreset.balanced);
      expect(
        ImageCompressionPreset.parse(null),
        ImageCompressionPreset.balanced,
      );
      expect(
        ImageCompressionPreset.parse('original'),
        ImageCompressionPreset.original,
      );
      expect(prefs.shareUploadCategories, true);
      expect(
        prefs
            .copyWith(shareUploadCategories: false)
            .copyWith(fontScale: 1.1)
            .shareUploadCategories,
        false,
      );
      expect(prefs.videoCompression, VideoCompressionPreset.balanced);
      expect(VideoCompressionPreset.smaller.targetBitrate, 1500000);
      expect(VideoCompressionPreset.balanced.targetBitrate, 4000000);
      expect(maximumPreparedVideoBytes, 512 * 1024 * 1024);
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
  test(
    'large GIF chat uploads are resized without flattening or losing metadata',
    () async {
      final first = image.Image(width: 1400, height: 20)..frameDuration = 100;
      final second = image.Image(width: 1400, height: 20)..frameDuration = 200;
      first.addFrame(second);
      final draft = AttachmentDraft(
        bytes: Uint8List.fromList(image.encodeGif(first)),
        name: 'animated.gif',
        mimeType: 'image/gif',
        spoiler: true,
        caption: 'caption',
        gifSource: Uri.parse('https://example.org/original.gif'),
      );
      final prepared = await prepareImage(
        draft,
        ImageCompressionPreset.smaller,
      );
      final decoded = image.decodePng(prepared.bytes)!;
      expect(decoded.width, 1280);
      expect(decoded.numFrames, 2);
      expect(prepared.caption, draft.caption);
      expect(prepared.spoiler, isTrue);
      expect(prepared.gifSource, draft.gifSource);
    },
  );
}
