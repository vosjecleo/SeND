import 'package:flutter_quill/flutter_quill.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

const spoilerEditorColor = '#010101';

({String plainText, String? html}) serializeRichMessage(Document document) {
  final plainText = document.toPlainText().trimRight();
  final operations = document
      .toDelta()
      .toJson()
      .map((operation) => Map<String, dynamic>.from(operation))
      .toList(growable: false);
  final hasFormatting = operations.any(
    (operation) => (operation['attributes'] as Map?)?.isNotEmpty == true,
  );
  if (!hasFormatting) return (plainText: plainText, html: null);

  final converter = QuillDeltaToHtmlConverter(
    operations,
    ConverterOptions.forEmail(),
  );
  var html = converter.convert();
  // Quill has no Matrix spoiler attribute. A reserved editor-only background
  // color provides the WYSIWYG treatment, then becomes the standard Matrix
  // data-mx-spoiler element on the wire.
  html = html.replaceAll(
    RegExp(
      r'<span style="background-color:\s*(?:#010101|rgb\(1,\s*1,\s*1\));?">',
      caseSensitive: false,
    ),
    '<span data-mx-spoiler>',
  );
  return (plainText: plainText, html: html);
}
