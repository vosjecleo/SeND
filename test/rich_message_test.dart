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

  test('converts typed markup without exposing formatting controls', () {
    final document = Document()..insert(0, '**bold** _italic_ ||hidden||');

    final message = serializeRichMessage(document);

    expect(message.plainText, '**bold** _italic_ ||hidden||');
    expect(message.html, contains('<strong>bold</strong>'));
    expect(message.html, contains('<em>italic</em>'));
    expect(message.html, contains('data-mx-spoiler'));
  });

  test('keeps filesystem paths as literal plain text', () {
    final document = Document()..insert(0, '/home/user/project/file.txt');

    final message = serializeRichMessage(document);

    expect(message.plainText, '/home/user/project/file.txt');
    expect(message.html, isNull);
  });
}
