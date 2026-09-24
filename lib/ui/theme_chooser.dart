import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';

const themeNames = {
  DeltiecordThemeMode.light: 'Light',
  DeltiecordThemeMode.regular: 'Gray',
  DeltiecordThemeMode.dark: 'Dark',
  DeltiecordThemeMode.night: 'Night',
};

class ThemeChooser extends StatelessWidget {
  const ThemeChooser({
    required this.value,
    required this.onChanged,
    this.customActive = false,
    super.key,
  });
  final bool customActive;
  final DeltiecordThemeMode value;
  final ValueChanged<DeltiecordThemeMode> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    key: const Key('theme-chooser'),
    contentPadding: EdgeInsets.zero,
    leading: _Swatch(value),
    title: Text(customActive ? 'Switch to a built-in theme' : 'Theme'),
    subtitle: customActive ? null : Text(themeNames[value]!),
    trailing: const Icon(Icons.expand_more),
    onTap: () async {
      final next = await showDialog<DeltiecordThemeMode>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose theme'),
          children: [
            for (final entry in themeNames.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, entry.key),
                child: Row(
                  children: [
                    _Swatch(entry.key),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry.value)),
                    const SizedBox(width: 12),
                    Icon(
                      entry.key == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (next != null) onChanged(next);
    },
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.mode);
  final DeltiecordThemeMode mode;
  @override
  Widget build(BuildContext context) {
    final palette = DeltiecordPalette.forMode(mode);
    return Container(
      width: 32,
      height: 24,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      alignment: Alignment.center,
      child: Container(width: 18, height: 3, color: palette.text),
    );
  }
}
