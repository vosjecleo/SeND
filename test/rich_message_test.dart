import 'package:deltiecord/ui/rich_message.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes rich text and Matrix spoilers with a plain fallback', () {
    final document = Document()..insert(0, 'bold secret');
    document.format(0, 4, Attribute.bold);
    document.format(5, 6, const BackgroundAttribute(spoilerEditorColor));

    final message = serializeRichMessage(document);

    expect(message.plainText, 'bold secret');
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('data-mx-spoiler'));
    expect(message.html, isNot(contains(spoilerEditorColor)));
  });
}
