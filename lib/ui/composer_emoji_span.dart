import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../services/custom_emoji.dart';
import 'matrix_html_text.dart';

/// Display selected emoji while retaining Quill's underlying alias offsets.
/// Plain typed aliases have no internal link and stay literal text.
InlineSpan composerEmojiSpan({
  required ChatBackend backend,
  required String text,
  required String? link,
  TextStyle? style,
  GestureRecognizer? recognizer,
}) {
  final emoji = customEmojiFromEditorLink(link);
  if (emoji == null || !text.contains(emoji.fallback)) {
    return TextSpan(text: text, style: style, recognizer: recognizer);
  }
  final children = <InlineSpan>[];
  var cursor = 0;
  while (cursor < text.length) {
    final start = text.indexOf(emoji.fallback, cursor);
    if (start < 0) {
      children.add(TextSpan(text: text.substring(cursor)));
      break;
    }
    if (start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, start)));
    }
    children.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: CustomEmojiImage(
          backend: backend,
          emoji: emoji,
          size: (style?.fontSize ?? 14) * 1.4,
        ),
      ),
    );
    // WidgetSpan consumes one document position. Preserve the other positions
    // so selection, deletion, and serialization keep their original offsets.
    for (var i = 1; i < emoji.fallback.length; i++) {
      children.add(const WidgetSpan(child: SizedBox.shrink()));
    }
    cursor = start + emoji.fallback.length;
  }
  return TextSpan(style: style, children: children);
}
