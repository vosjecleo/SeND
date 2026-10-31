import 'package:deltiecord/services/clipboard_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  test('clipboard prefers original animated formats over flattened PNG', () {
    expect(clipboardImageFormats.first, Formats.gif);
    expect(
      clipboardImageFormats.indexOf(Formats.webp),
      lessThan(clipboardImageFormats.indexOf(Formats.png)),
    );
  });
}
