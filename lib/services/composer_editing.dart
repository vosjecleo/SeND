import 'package:flutter/services.dart';

/// The visible edge of an emoji represents the end of its backing shortcode.
/// Invisible placeholder positions must never become editable caret stops.
TextEditingValue normalizeEmojiCaret(
  TextEditingValue value,
  Iterable<TextRange> tokens,
) {
  if (!value.selection.isValid ||
      !value.selection.isCollapsed ||
      !value.composing.isCollapsed) {
    return value;
  }
  final offset = value.selection.extentOffset;
  for (final token in tokens) {
    if (offset > token.start &&
        offset < token.end &&
        token.end <= value.text.length) {
      return value.copyWith(
        selection: TextSelection.collapsed(offset: token.end),
      );
    }
  }
  return value;
}

TextEditingValue repairEmojiBackspace(
  TextEditingValue oldValue,
  TextEditingValue newValue,
  Iterable<TextRange> tokens,
) {
  if (!oldValue.selection.isCollapsed ||
      !oldValue.selection.isValid ||
      !oldValue.composing.isCollapsed ||
      !newValue.composing.isCollapsed ||
      oldValue.text.length - newValue.text.length != 1) {
    return newValue;
  }
  final caret = oldValue.selection.extentOffset;
  for (final token in tokens) {
    if (caret > token.start &&
        caret < token.end &&
        token.end <= oldValue.text.length &&
        oldValue.text.replaceRange(caret - 1, caret, '') == newValue.text) {
      return TextEditingValue(
        text: oldValue.text.replaceRange(token.end - 1, token.end, ''),
        selection: TextSelection.collapsed(offset: token.end - 1),
      );
    }
  }
  return newValue;
}
