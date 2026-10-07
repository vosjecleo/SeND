import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/ui/plain_message_editor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TextEditingValue delete(String text, int cursor, {bool custom = true}) {
    final document = Document()..insert(0, text);
    if (custom) {
      final emoji = CustomEmojiReference(
        id: Uri.parse('mxc://test/wave'),
        name: 'wave',
      );
      for (final match in RegExp(':wave:').allMatches(text)) {
        document.format(
          match.start,
          6,
          LinkAttribute(customEmojiEditorLink(emoji)),
        );
      }
    }
    final controller = QuillController(
      document: document,
      selection: TextSelection.collapsed(offset: cursor),
    );
    final result = CustomEmojiDeletionFormatter(controller).formatEditUpdate(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      ),
      TextEditingValue(
        text: text.replaceRange(cursor - 1, cursor, ''),
        selection: TextSelection.collapsed(offset: cursor - 1),
      ),
    );
    controller.dispose();
    return result;
  }

  test('backspace removes a whole selected custom emoji', () {
    final result = delete('hi :wave:', 9);
    expect(result.text, 'hi ');
    expect(result.selection.baseOffset, 3);
  });
  test('deletion inside a rendered shortcode removes the emoji', () {
    expect(delete(':wave:!', 1).text, '!');
  });
  test('adjacent identical emojis remain separate editing units', () {
    expect(delete(':wave::wave:', 6).text, ':wave:');
    expect(delete(':wave::wave:', 12).text, ':wave:');
  });
  test('ordinary typed shortcodes remain plain text', () {
    expect(delete(':wave:', 6, custom: false).text, ':wave');
  });
  test('ordinary text next to custom emoji deletes normally', () {
    expect(delete(':wave: hi', 9).text, ':wave: h');
  });
}
