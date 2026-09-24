import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../services/custom_emoji.dart';
import '../models/chat_models.dart';

const spoilerEditorColor = '#010101';

/// Clearing text alone preserves Quill's terminal paragraph and pending
/// clipboard styles (including background colours). A new message is a new
/// document, not a deletion within the previous formatted paragraph.
void resetRichComposer(QuillController controller) {
  controller.toggledStyle = const Style();
  controller.document = Document();
}

/// Keep existing formatting on mobile edits while its platform text field
/// handles IME input. Only the changed range is replaced, not the whole draft.
void reconcileRichMessageDocument(
  Document document,
  String before,
  String after,
) {
  if (before == after) return;
  var start = 0;
  while (start < before.length &&
      start < after.length &&
      before.codeUnitAt(start) == after.codeUnitAt(start)) {
    start++;
  }
  var oldEnd = before.length;
  var newEnd = after.length;
  while (oldEnd > start &&
      newEnd > start &&
      before.codeUnitAt(oldEnd - 1) == after.codeUnitAt(newEnd - 1)) {
    oldEnd--;
    newEnd--;
  }
  if (oldEnd > start) document.delete(start, oldEnd - start);
  if (newEnd > start) document.insert(start, after.substring(start, newEnd));
}

/// Markdown and selected custom emoji share one serialization path. A selected
/// emoji must not disable formatting elsewhere in the draft.
({String plainText, String? html}) serializeMarkdownEmojiMessage(
  String text,
  List<CustomEmojiTextSpan> emojis,
) {
  if (emojis.isEmpty) {
    return (
      plainText: text.trimRight(),
      html: _typedMarkupToHtml(text.trimRight()),
    );
  }
  var prefix = 'DELTIECORDEMOJITOKEN';
  while (text.contains(prefix)) {
    prefix += 'X';
  }
  final replacements = <String, String>{};
  var cursor = 0;
  final masked = StringBuffer();
  for (final span in (List<CustomEmojiTextSpan>.of(
    emojis,
  )..sort((a, b) => a.start.compareTo(b.start)))) {
    if (span.start < cursor ||
        span.end > text.length ||
        span.end <= span.start ||
        text.substring(span.start, span.end) != span.emoji.fallback) {
      continue;
    }
    masked.write(text.substring(cursor, span.start));
    final token = '$prefix${replacements.length}END';
    replacements[token] = customEmojiHtml(span.emoji);
    masked.write(token);
    cursor = span.end;
  }
  masked.write(text.substring(cursor));
  final source = masked.toString().trimRight();
  var html =
      _typedMarkupToHtml(source) ??
      htmlEscape.convert(source).replaceAll('\n', '<br>');
  for (final entry in replacements.entries) {
    html = html.replaceAll(entry.key, entry.value);
  }
  return (plainText: text.trimRight(), html: html);
}

/// Restore supported Matrix formatting rather than flattening an edit to body.
/// External images stay text; custom emoji use our existing stable editor links.
Document richMessageDocument(String body, String? html) {
  if (html == null || html.isEmpty) return Document()..insert(0, body);
  final fragment = html_parser.parseFragment(html);
  for (final reply in fragment.querySelectorAll('mx-reply')) {
    reply.remove();
  }
  for (final image in fragment.querySelectorAll('img')) {
    final uri = Uri.tryParse(image.attributes['src'] ?? '');
    final fallback = image.attributes['alt'] ?? image.attributes['title'] ?? '';
    if (image.attributes.containsKey('data-mx-emoticon') &&
        uri?.scheme == 'mxc' &&
        fallback.isNotEmpty) {
      final emoji = CustomEmojiReference(
        id: uri!,
        name: fallback.replaceAll(RegExp(r'^:|:$'), ''),
      );
      image.replaceWith(
        dom.Element.tag('a')
          ..attributes['href'] = customEmojiEditorLink(emoji)
          ..text = fallback,
      );
    } else {
      image.replaceWith(dom.Text(fallback));
    }
  }
  for (final spoiler in fragment.querySelectorAll('[data-mx-spoiler]')) {
    spoiler.attributes['style'] = 'background-color: $spoilerEditorColor';
  }
  try {
    return Document.fromDelta(HtmlToDelta().convert(fragment.outerHtml));
  } catch (_) {
    // Malformed remote markup must remain editable without losing its body.
    return Document()..insert(0, body);
  }
}

// Serialization composes flutter_quill, vsc_quill_delta_to_html, and the Dart
// markdown package. No editor implementation is vendored; see CREDITS.md.
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
  if (!hasFormatting) {
    return (plainText: plainText, html: _typedMarkupToHtml(plainText));
  }

  final onlyEmojiFormatting = operations.every((operation) {
    final attributes = operation['attributes'] as Map?;
    return attributes == null ||
        attributes.isEmpty ||
        (attributes.length == 1 &&
            customEmojiFromEditorLink(attributes['link'] as String?) != null);
  });
  if (onlyEmojiFormatting) {
    var offset = 0;
    final emojis = <CustomEmojiTextSpan>[];
    for (final operation in operations) {
      final inserted = operation['insert'];
      if (inserted is! String) continue;
      final emoji = customEmojiFromEditorLink(
        (operation['attributes'] as Map?)?['link'] as String?,
      );
      if (emoji != null) {
        for (final match in RegExp(
          RegExp.escape(emoji.fallback),
        ).allMatches(inserted)) {
          emojis.add(
            CustomEmojiTextSpan(
              start: offset + match.start,
              end: offset + match.end,
              emoji: emoji,
            ),
          );
        }
      }
      offset += inserted.length;
    }
    return serializeMarkdownEmojiMessage(plainText, emojis);
  }

  final converter = QuillDeltaToHtmlConverter(
    operations,
    ConverterOptions.forEmail(),
  );
  var html = converter.convert();
  html = replaceCustomEmojiEditorLinks(html);
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

String? _typedMarkupToHtml(String text) {
  final hasMarkup = RegExp(
    r'(^|\n)\s*(?:>|[-*+]\s|\d+\.\s|```)|(^|[\s(])(?:\*\*?\S|_\S|`\S|~~\S|\|\|\S)|\[[^\]]+\]\(',
  ).hasMatch(text);
  if (!hasMarkup) return null;

  final spoilers = <String>[];
  final withTokens = text.replaceAllMapped(RegExp(r'\|\|(.+?)\|\|'), (match) {
    final token = 'DELTIECORDSPOILER${spoilers.length}TOKEN';
    spoilers.add(htmlEscape.convert(match.group(1)!));
    return token;
  });
  var html = markdown.markdownToHtml(
    withTokens,
    extensionSet: markdown.ExtensionSet.gitHubWeb,
  );
  for (var index = 0; index < spoilers.length; index++) {
    html = html.replaceAll(
      'DELTIECORDSPOILER${index}TOKEN',
      '<span data-mx-spoiler>${spoilers[index]}</span>',
    );
  }
  return html;
}
