import 'dart:convert';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as markdown;

import '../services/custom_emoji.dart';
import '../models/chat_models.dart';

/// Import only text and explicit custom-emoji identities into the plain editor.
Document plainMessageDocument(String body, String? html) {
  final document = Document()..insert(0, body);
  for (final span in customEmojiSpansFromHtml(html, body)) {
    document.format(
      span.start,
      span.end - span.start,
      LinkAttribute(customEmojiEditorLink(span.emoji)),
    );
  }
  return document;
}

/// Old drafts can contain styles. Never bring them back into the plain composer
/// or outgoing messages; only selected emoji and Matrix mention links survive.
({String plainText, String? html}) serializePlainComposer(Document document) {
  final plain = document.toPlainText().trimRight();
  var prefix = 'SENDSELECTEDTOKEN';
  while (plain.contains(prefix)) {
    prefix += 'X';
  }
  final replacements = <String, String>{};
  final masked = StringBuffer();
  for (final operation in document.toDelta().toJson()) {
    final inserted = operation['insert'];
    if (inserted is! String) continue;
    final link = (operation['attributes'] as Map?)?['link'] as String?;
    final emoji = customEmojiFromEditorLink(link);
    String token(String html) {
      final key = '$prefix${replacements.length}END';
      replacements[key] = html;
      return key;
    }

    if (emoji != null) {
      masked.write(
        inserted.replaceAllMapped(
          RegExp(RegExp.escape(emoji.fallback)),
          (_) => token(customEmojiHtml(emoji)),
        ),
      );
    } else if (link != null && link.startsWith('https://matrix.to/#/')) {
      masked.write(
        token(
          '<a href="${htmlEscape.convert(link)}">${htmlEscape.convert(inserted)}</a>',
        ),
      );
    } else {
      masked.write(inserted);
    }
  }
  if (replacements.isEmpty) {
    return serializeMarkdownEmojiMessage(plain, const []);
  }
  final source = masked.toString().trimRight();
  var html =
      _typedMarkupToHtml(source) ??
      htmlEscape.convert(source).replaceAll('\n', '<br>');
  for (final entry in replacements.entries) {
    html = html.replaceAll(entry.key, entry.value);
  }
  return (plainText: plain, html: html);
}

/// Clearing text alone preserves Quill's terminal paragraph and pending
/// clipboard styles (including background colours). A new message is a new
/// document, not a deletion within the previous formatted paragraph.
void resetRichComposer(QuillController controller) {
  controller.toggledStyle = const Style();
  controller.document = Document();
}

/// Preserve stable custom-emoji/mention ranges while native text input handles
/// IME input. Only the changed range is replaced, not the whole draft.
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

String? _typedMarkupToHtml(String text) {
  if (!RegExp(r'[*_~]|\|\|').hasMatch(text)) return null;

  var prefix = 'SENDINLINESPOILER';
  while (text.contains(prefix)) {
    prefix += 'X';
  }
  final spoilers = <String>[];
  final source = text.replaceAllMapped(RegExp(r'\|\|(.+?)\|\|'), (match) {
    final token = '$prefix${spoilers.length}END';
    spoilers.add(htmlEscape.convert(match.group(1)!));
    return token;
  });
  // Deliberately parse inline only: no paragraphs, quotes, lists, headings,
  // tables, code blocks, raw HTML, or implicit formatting from pasted content.
  final document = markdown.Document(
    withDefaultBlockSyntaxes: false,
    withDefaultInlineSyntaxes: false,
    inlineSyntaxes: [
      markdown.EscapeSyntax(),
      markdown.EmphasisSyntax.asterisk(),
      markdown.DelimiterSyntax(
        '_+',
        requiresDelimiterRun: true,
        tags: [markdown.DelimiterTag('em', 1), markdown.DelimiterTag('u', 2)],
      ),
      markdown.StrikethroughSyntax(),
      _ComposerLineBreakSyntax(),
    ],
  );
  // The renderer pretty-prints <br> with a source newline. That newline is
  // not message content and HTML clients can turn it into an unwanted space.
  var html = markdown
      .renderToHtml(document.parseInline(source))
      .replaceAll('<br />\n', '<br>');
  for (var index = 0; index < spoilers.length; index++) {
    html = html.replaceAll(
      '$prefix${index}END',
      '<span data-mx-spoiler>${spoilers[index]}</span>',
    );
  }
  return html == text ? null : html;
}

class _ComposerLineBreakSyntax extends markdown.InlineSyntax {
  _ComposerLineBreakSyntax() : super(r'\n');
  @override
  bool onMatch(markdown.InlineParser parser, Match match) {
    parser.addNode(markdown.Element.empty('br'));
    return true;
  }
}
