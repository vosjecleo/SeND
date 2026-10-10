import 'package:flutter/material.dart';

// Keep source offsets intact. This changes paint, never the draft or selection.
final inlineMarkupPattern = RegExp(r'(\*\*|__|~~|\|\||\*|_)([^\n]+?)\1');

TextSpan inlineComposerPreview(String text, TextStyle? style) {
  final children = <InlineSpan>[];
  var offset = 0;
  for (final match in inlineMarkupPattern.allMatches(text)) {
    children.add(TextSpan(text: text.substring(offset, match.start)));
    final delimiter = match.group(1)!;
    final content = match.group(2)!;
    if (content.contains('\\') ||
        (match.start > 0 && text[match.start - 1] == '\\')) {
      children.add(TextSpan(text: match.group(0)));
    } else {
      final base = style ?? const TextStyle();
      final marker = base.copyWith(
        color: (base.color ?? Colors.grey).withValues(alpha: .5),
      );
      final body = switch (delimiter) {
        '**' || '__' => base.copyWith(fontWeight: FontWeight.bold),
        '*' || '_' => base.copyWith(fontStyle: FontStyle.italic),
        '~~' => base.copyWith(decoration: TextDecoration.lineThrough),
        _ => base.copyWith(backgroundColor: const Color(0x40777777)),
      };
      children.addAll([
        TextSpan(text: delimiter, style: marker),
        TextSpan(text: content, style: body),
        TextSpan(text: delimiter, style: marker),
      ]);
    }
    offset = match.end;
  }
  children.add(TextSpan(text: text.substring(offset)));
  return TextSpan(style: style, children: children);
}
