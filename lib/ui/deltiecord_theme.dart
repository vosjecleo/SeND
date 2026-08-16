import 'package:flutter/material.dart';

import '../models/chat_models.dart';

@immutable
class DeltiecordPalette extends ThemeExtension<DeltiecordPalette> {
  const DeltiecordPalette({
    required this.background,
    required this.rail,
    required this.panel,
    required this.surface,
    required this.elevated,
    required this.input,
    required this.hover,
    required this.divider,
    required this.text,
    required this.muted,
  });

  final Color background;
  final Color rail;
  final Color panel;
  final Color surface;
  final Color elevated;
  final Color input;
  final Color hover;
  final Color divider;
  final Color text;
  final Color muted;

  static DeltiecordPalette forMode(DeltiecordThemeMode mode) => switch (mode) {
    DeltiecordThemeMode.light => const DeltiecordPalette(
      background: Color(0xffffffff),
      rail: Color(0xffe3e5e8),
      panel: Color(0xfff2f3f5),
      surface: Color(0xfff2f3f5),
      elevated: Color(0xffe3e5e8),
      input: Color(0xffffffff),
      hover: Color(0xffe3e5e8),
      divider: Color(0xffe3e5e8),
      text: Color(0xff202225),
      muted: Color(0xff5c6068),
    ),
    DeltiecordThemeMode.dark => const DeltiecordPalette(
      background: Color(0xff313338),
      rail: Color(0xff1e1f22),
      panel: Color(0xff2b2d31),
      surface: Color(0xff313338),
      elevated: Color(0xff2b2d31),
      input: Color(0xff1e1f22),
      hover: Color(0xff2b2d31),
      divider: Color(0xff1e1f22),
      text: Color(0xfff2f3f5),
      muted: Color(0xffb5bac1),
    ),
    DeltiecordThemeMode.oled => const DeltiecordPalette(
      background: Color(0xff000000),
      rail: Color(0xff000000),
      panel: Color(0xff000000),
      surface: Color(0xff000000),
      elevated: Color(0xff000000),
      input: Color(0xff000000),
      hover: Color(0xff000000),
      divider: Color(0xff292929),
      text: Color(0xfff5f5f5),
      muted: Color(0xffa9a9ad),
    ),
  };

  @override
  DeltiecordPalette copyWith({
    Color? background,
    Color? rail,
    Color? panel,
    Color? surface,
    Color? elevated,
    Color? input,
    Color? hover,
    Color? divider,
    Color? text,
    Color? muted,
  }) => DeltiecordPalette(
    background: background ?? this.background,
    rail: rail ?? this.rail,
    panel: panel ?? this.panel,
    surface: surface ?? this.surface,
    elevated: elevated ?? this.elevated,
    input: input ?? this.input,
    hover: hover ?? this.hover,
    divider: divider ?? this.divider,
    text: text ?? this.text,
    muted: muted ?? this.muted,
  );

  @override
  DeltiecordPalette lerp(covariant DeltiecordPalette? other, double t) {
    if (other == null) return this;
    return DeltiecordPalette(
      background: Color.lerp(background, other.background, t)!,
      rail: Color.lerp(rail, other.rail, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      input: Color.lerp(input, other.input, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
    );
  }
}

extension DeltiecordThemeContext on BuildContext {
  DeltiecordPalette get deltiecord =>
      Theme.of(this).extension<DeltiecordPalette>()!;
}
