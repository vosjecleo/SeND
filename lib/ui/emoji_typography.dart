import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final colourEmojiPattern = RegExp(
  r'[\u{00A9}\u{00AE}\u{203C}\u{2049}\u{2122}\u{2139}\u{2194}-\u{21FF}\u{2300}-\u{23FF}\u{25A0}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F000}-\u{1FAFF}]',
  unicode: true,
);

TextSpan colourEmojiTextSpan(String text, TextStyle? style) {
  if (!colourEmojiPattern.hasMatch(text)) {
    return TextSpan(text: text, style: style);
  }
  final children = <InlineSpan>[];
  final buffer = StringBuffer();
  bool? emoji;
  void flush() {
    if (buffer.isEmpty) return;
    children.add(
      TextSpan(
        text: buffer.toString(),
        style: emoji == true
            ? colourEmojiStyle(style ?? const TextStyle())
            : style,
      ),
    );
    buffer.clear();
  }

  for (final cluster in text.characters) {
    final next = colourEmojiPattern.hasMatch(cluster);
    if (emoji != null && next != emoji) flush();
    emoji = next;
    buffer.write(cluster);
  }
  flush();
  return TextSpan(style: style, children: children);
}

/// Emoji spans must not inherit the interface font's monochrome symbol glyphs.
/// The OS still supplies the font; we do not bundle or rewrite Unicode data.
TextStyle colourEmojiStyle(TextStyle base) => base.copyWith(
  fontFamily: switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => 'Apple Color Emoji',
    TargetPlatform.windows => 'Segoe UI Emoji',
    _ => 'Noto Color Emoji',
  },
  fontFamilyFallback: const [
    'Noto Color Emoji',
    'Apple Color Emoji',
    'Segoe UI Emoji',
  ],
  fontWeight: FontWeight.normal,
  fontStyle: FontStyle.normal,
);
