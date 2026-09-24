import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
