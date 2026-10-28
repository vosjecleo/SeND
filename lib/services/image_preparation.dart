import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import 'encoded_image_dimensions.dart';
import 'image_animation.dart';

Future<AttachmentDraft> prepareImage(
  AttachmentDraft draft,
  ImageCompressionPreset preset,
) async {
  if (!draft.mimeType.startsWith('image/') ||
      preset == ImageCompressionPreset.original ||
      draft.imagePrepared ||
      hasAnimatedImageHeader(draft.bytes)) {
    return draft;
  }
  final size = await readEncodedImageDimensions(draft.bytes);
  if (size == null || size.width * size.height > 32000000) {
    throw StateError(
      'This image is too large to resize safely. Choose original quality.',
    );
  }
  final result = await compute(_resize, (
    bytes: draft.bytes,
    small: preset == ImageCompressionPreset.smaller,
  ));
  if (result == null || result.bytes.length >= draft.bytes.length) return draft;
  final extension = result.png ? 'png' : 'jpg';
  return draft.copyWith(
    bytes: result.bytes,
    name: '${draft.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.$extension',
    mimeType: 'image/${result.png ? 'png' : 'jpeg'}',
    imagePrepared: true,
  );
}

({Uint8List bytes, bool png})? _resize(({Uint8List bytes, bool small}) input) {
  final decoded = image.decodeImage(input.bytes);
  if (decoded == null || decoded.numFrames > 1) return null;
  final oriented = image.bakeOrientation(decoded);
  final edge = input.small ? 1280 : 2048;
  final width = oriented.width >= oriented.height
      ? edge
      : (edge * oriented.width / oriented.height).round();
  final height = oriented.height >= oriented.width
      ? edge
      : (edge * oriented.height / oriented.width).round();
  final resized = oriented.width > edge || oriented.height > edge
      ? image.copyResize(
          oriented,
          width: width,
          height: height,
          interpolation: image.Interpolation.average,
        )
      : oriented;
  final png = resized.hasAlpha;
  return (
    bytes: Uint8List.fromList(
      png
          ? image.encodePng(resized)
          : image.encodeJpg(resized, quality: input.small ? 75 : 85),
    ),
    png: png,
  );
}
