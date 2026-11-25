import 'dart:typed_data';
import 'dart:ui' as ui;
import 'encoded_image_dimensions.dart';

/// Decode just one frame into a small browsing preview, never an animation.
Future<Uint8List> imageGridPreview(Uint8List bytes) async {
  final size = await readEncodedImageDimensions(bytes, maximumPixels: 32000000);
  if (size == null) throw const FormatException('Image exceeds preview limits');
  final edge = size.width > size.height ? size.width : size.height;
  final scale = edge > 256 ? 256 / edge : 1.0;
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: (size.width * scale).round().clamp(1, 256),
    targetHeight: (size.height * scale).round().clamp(1, 256),
    allowUpscaling: false,
  );
  try {
    final frame = await codec.getNextFrame();
    try {
      final encoded = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (encoded == null) {
        throw const FormatException('Could not make preview');
      }
      return encoded.buffer.asUint8List(
        encoded.offsetInBytes,
        encoded.lengthInBytes,
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
