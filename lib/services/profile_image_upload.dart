import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:mime/mime.dart';

import 'encoded_image_dimensions.dart';
import 'image_animation.dart';

enum ProfileImageRole {
  avatar(512),
  banner(1920),
  voiceBackground(1600),
  activityIcon(256),
  sticker(512);

  const ProfileImageRole(this.maximumEdge);
  final int maximumEdge;
}

class PreparedProfileImage {
  const PreparedProfileImage(this.bytes, this.mimeType);
  final Uint8List bytes;
  final String mimeType;
  String get extension => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    _ => 'png',
  };
}

/// Enforced at upload boundaries, including callers that bypass crop dialogs.
/// Small images are never enlarged; animation, alpha and frame timing survive.
Future<PreparedProfileImage> prepareProfileImage(
  Uint8List bytes,
  ProfileImageRole role,
) async {
  final size = await readEncodedImageDimensions(bytes, maximumPixels: 32000000);
  if (size == null) {
    throw StateError(
      'This image cannot be resized safely. Choose a smaller image.',
    );
  }
  final edge = role.maximumEdge;
  final resize = size.width > edge || size.height > edge;
  final animated = hasAnimatedImageHeader(bytes);
  PreparedProfileImage result;
  if (animated && !resize) {
    result = PreparedProfileImage(
      bytes,
      lookupMimeType('image', headerBytes: bytes) ?? 'image/png',
    );
  } else if (animated) {
    result = PreparedProfileImage(
      await resizeAnimatedUpload(bytes, size, edge),
      'image/png',
    );
  } else {
    final prepared = await compute(_resizeStatic, (bytes: bytes, edge: edge));
    final mime = lookupMimeType('image', headerBytes: bytes);
    result =
        !resize &&
            prepared.bytes.length >= bytes.length &&
            const ['image/png', 'image/jpeg', 'image/webp'].contains(mime)
        ? PreparedProfileImage(bytes, mime!)
        : prepared;
  }
  if (result.bytes.length > 8 * 1024 * 1024) {
    throw StateError(
      'This image is too large. Choose a smaller or shorter image.',
    );
  }
  return result;
}

PreparedProfileImage _resizeStatic(({Uint8List bytes, int edge}) input) {
  final decoded = image.decodeImage(input.bytes);
  if (decoded == null) throw const FormatException('Could not decode image');
  var pixels = image.bakeOrientation(decoded);
  if (pixels.width > input.edge || pixels.height > input.edge) {
    final scale =
        input.edge /
        (pixels.width > pixels.height ? pixels.width : pixels.height);
    pixels = image.copyResize(
      pixels,
      width: (pixels.width * scale).round().clamp(1, input.edge),
      height: (pixels.height * scale).round().clamp(1, input.edge),
      interpolation: image.Interpolation.average,
    );
  }
  final transparent =
      pixels.hasAlpha && pixels.any((pixel) => pixel.a < pixel.maxChannelValue);
  return PreparedProfileImage(
    Uint8List.fromList(
      transparent
          ? image.encodePng(pixels, level: 6)
          : image.encodeJpg(pixels, quality: 85),
    ),
    transparent ? 'image/png' : 'image/jpeg',
  );
}

Future<Uint8List> resizeAnimatedUpload(
  Uint8List bytes,
  ({int width, int height}) size,
  int edge,
) async {
  final scale = edge / (size.width > size.height ? size.width : size.height);
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: (size.width * scale).round().clamp(1, edge),
    targetHeight: (size.height * scale).round().clamp(1, edge),
    allowUpscaling: false,
  );
  try {
    if (codec.frameCount > 1500 ||
        size.width * size.height * codec.frameCount > 150000000) {
      throw StateError(
        'This animation is too large. Choose a smaller or shorter image.',
      );
    }
    final encoder = image.PngEncoder(level: 6)
      ..repeat = codec.repetitionCount < 0 ? 0 : codec.repetitionCount + 1
      ..start(codec.frameCount);
    for (var index = 0; index < codec.frameCount; index++) {
      final frame = await codec.getNextFrame();
      try {
        final pixels = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawStraightRgba,
        );
        if (pixels == null) throw const FormatException('Could not read image');
        var rgba = image.Image.fromBytes(
          width: frame.image.width,
          height: frame.image.height,
          bytes: pixels.buffer,
          bytesOffset: pixels.offsetInBytes,
          numChannels: 4,
        )..frameDuration = frame.duration.inMilliseconds;
        // Animated GIF codecs can ignore targetWidth/targetHeight. Resize the
        // composited frame too, without losing its palette, alpha or timing.
        if (rgba.width > edge || rgba.height > edge) {
          final frameScale =
              edge / (rgba.width > rgba.height ? rgba.width : rgba.height);
          rgba = image.copyResize(
            rgba,
            width: (rgba.width * frameScale).round().clamp(1, edge),
            height: (rgba.height * frameScale).round().clamp(1, edge),
            interpolation: image.Interpolation.average,
          )..frameDuration = frame.duration.inMilliseconds;
        }
        encoder.addFrame(rgba);
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
