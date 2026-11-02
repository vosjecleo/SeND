import 'package:flutter/material.dart';
import 'emoji_typography.dart';

// Keep source offsets intact. This changes paint, never the draft or selection.
final inlineMarkupPattern = RegExp(r'(\*\*|__|~~|\|\||\*|_)([^\n]+?)\1');
final _mentionPattern = RegExp(
  r'(?<![A-Za-z0-9_@/\\])@(?:[A-Za-z0-9._=/-]+:[A-Za-z0-9][A-Za-z0-9.:-]*|everyone|all|room)(?![A-Za-z0-9_:/-]|\.[A-Za-z0-9])',
);

TextSpan _composerText(String text, TextStyle? style) {
  if (!_mentionPattern.hasMatch(text)) return colourEmojiTextSpan(text, style);
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in _mentionPattern.allMatches(text)) {
    spans.add(colourEmojiTextSpan(text.substring(offset, match.start), style));
    spans.add(
      TextSpan(
        text: match.group(0),
        style: (style ?? const TextStyle()).copyWith(
          color: const Color(0xff408cff),
          backgroundColor: const Color(0x403fa9f5),
        ),
      ),
    );
    offset = match.end;
  }
  spans.add(colourEmojiTextSpan(text.substring(offset), style));
  return TextSpan(style: style, children: spans);
}

TextSpan inlineComposerPreview(String text, TextStyle? style) {
  final children = <InlineSpan>[];
  var offset = 0;
  for (final match in inlineMarkupPattern.allMatches(text)) {
    children.add(_composerText(text.substring(offset, match.start), style));
    final delimiter = match.group(1)!;
    final content = match.group(2)!;
    if (content.contains('\\') ||
        (match.start > 0 && text[match.start - 1] == '\\')) {
      children.add(_composerText(match.group(0)!, style));
    } else {
      final base = style ?? const TextStyle();
      final marker = base.copyWith(
        color: (base.color ?? Colors.grey).withValues(alpha: .5),
      );
      final body = switch (delimiter) {
        '**' => base.copyWith(fontWeight: FontWeight.bold),
        '__' => base.copyWith(decoration: TextDecoration.underline),
        '*' || '_' => base.copyWith(fontStyle: FontStyle.italic),
        '~~' => base.copyWith(decoration: TextDecoration.lineThrough),
        _ => base.copyWith(backgroundColor: const Color(0x40777777)),
      };
      children.addAll([
        TextSpan(text: delimiter, style: marker),
        _composerText(content, body),
        TextSpan(text: delimiter, style: marker),
      ]);
    }
    offset = match.end;
  }
  children.add(_composerText(text.substring(offset), style));
  return TextSpan(style: style, children: children);
}
