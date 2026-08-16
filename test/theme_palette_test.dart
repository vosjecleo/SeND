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
        palette.hover,
      },
      {const Color(0xff000000)},
    );
  });

  test('new installs start at half compactness', () {
    expect(const AppPreferences().compactness, 0.5);
  });
}
