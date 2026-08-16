import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OLED uses true black for every background role', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.oled);
    expect(
      {
        palette.background,
        palette.rail,
        palette.panel,
        palette.surface,
        palette.elevated,
        palette.input,
        palette.island,
        palette.hover,
      },
      {const Color(0xff000000)},
    );
  });

  test('new installs start at half compactness', () {
    expect(const AppPreferences().compactness, 0.5);
  });

  test('dark mode distinguishes floating control islands', () {
    final palette = DeltiecordPalette.forMode(DeltiecordThemeMode.dark);
    expect(palette.background, const Color(0xff26272c));
    expect(palette.panel, const Color(0xff202125));
    expect(palette.input, const Color(0xff1e1f22));
    expect(palette.island, const Color(0xff2b2d31));
    expect(palette.island, isNot(palette.background));
  });
}
