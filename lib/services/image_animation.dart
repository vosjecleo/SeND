import 'dart:typed_data';

bool hasAnimatedImageHeader(Uint8List bytes) {
  bool at(int offset, String value) =>
      bytes.length >= offset + value.length &&
      List.generate(
        value.length,
        (i) => bytes[offset + i] == value.codeUnitAt(i),
      ).every((v) => v);
  if (at(0, 'GIF87a') || at(0, 'GIF89a')) return true;
  if (bytes.length >= 8 && bytes[0] == 137 && at(1, 'PNG\r\n\u001a\n')) {
    final data = ByteData.sublistView(bytes);
    for (var offset = 8; offset + 12 <= bytes.length;) {
      final length = data.getUint32(offset);
      if (length > bytes.length - offset - 12) return false;
      if (at(offset + 4, 'acTL')) return length == 8;
      if (at(offset + 4, 'IDAT') || at(offset + 4, 'IEND')) return false;
      offset += length + 12;
    }
  }
  return bytes.length >= 21 &&
      at(0, 'RIFF') &&
      at(8, 'WEBP') &&
      at(12, 'VP8X') &&
      (bytes[20] & 2) != 0;
}
