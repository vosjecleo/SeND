import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import 'accent_color_picker.dart';
import 'json_theme.dart';

class JsonThemeSettings extends StatefulWidget {
  const JsonThemeSettings({required this.backend, super.key});
  final ChatBackend backend;
  @override
  State<JsonThemeSettings> createState() => _JsonThemeSettingsState();
}

class _JsonThemeSettingsState extends State<JsonThemeSettings> {
  String? _error;
  bool _busy = false;

  Future<void> _select(Future<String> Function() load) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final source = await load();
      if (source.isEmpty || !mounted) return;
      final theme = JsonTheme.parse(source);
      // Validate resolution too, before replacing the working appearance.
      theme.resolve(
        widget.backend.preferences.copyWith(themeSettings: const {}),
      );
      await widget.backend.updatePreferences(
        widget.backend.preferences.copyWith(
          themeJson: source,
          themeSettings: const {},
        ),
      );
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open this JSON theme. Your current theme was kept.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _import() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: false,
      withReadStream: true,
    );
    if (result == null) return '';
    final file = result.files.single;
    if (file.size > JsonTheme.maxBytes) {
      throw const FormatException('Theme must be at most 64 KiB.');
    }
    final bytes = <int>[];
    final stream = file.readStream;
    if (stream != null) {
      await for (final chunk in stream) {
        if (bytes.length + chunk.length > JsonTheme.maxBytes) {
          throw const FormatException('Theme must be at most 64 KiB.');
        }
        bytes.addAll(chunk);
      }
    } else if (file.bytes != null) {
      bytes.addAll(file.bytes!);
    } else {
      throw const FormatException('This picker could not read the theme file.');
    }
    return utf8.decode(bytes);
  }

  void _set(String id, Object value) {
    final preferences = widget.backend.preferences;
    widget.backend.updatePreferences(
      preferences.copyWith(
        themeSettings: Map.unmodifiable({
          ...preferences.themeSettings,
          id: value,
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.backend.preferences;
    JsonTheme? theme;
    if (preferences.themeJson.isNotEmpty) {
      try {
        theme = JsonTheme.parse(preferences.themeJson);
      } catch (_) {
        /* Safe fallback remains selectable. */
      }
    }
    final values =
        theme?.values(preferences.themeSettings) ?? const <String, Object?>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Custom theme'),
          subtitle: Text(
            theme?.name ??
                (preferences.themeJson.isEmpty
                    ? 'Default Deltiecord appearance'
                    : 'Unavailable theme — using built-in colours'),
          ),
          trailing: preferences.themeJson.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Use default appearance',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: () => widget.backend.updatePreferences(
                    preferences.copyWith(
                      themeJson: '',
                      themeSettings: const {},
                    ),
                  ),
                ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _select(
                      () => rootBundle.loadString('assets/themes/aero.json'),
                    ),
              icon: const Icon(Icons.blur_on),
              label: const Text('Try Aero Glass'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _select(_import),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import JSON theme'),
            ),
            if (theme != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert({
                        ...theme!.document,
                        'settings': [
                          for (final setting in theme.settings)
                            {...setting, 'default': values[setting['id']]},
                        ],
                      }),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Theme JSON copied.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy theme JSON'),
              ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (theme != null) ...[
          const SizedBox(height: 12),
          for (final setting in theme.settings)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _control(setting, values[setting['id']]!),
            ),
          const Text(
            'Theme settings follow your appearance sync choice. High contrast disables glass effects; reduced motion disables blur.',
          ),
        ],
      ],
    );
  }

  Widget _control(Map<String, dynamic> setting, Object value) {
    final id = setting['id'] as String;
    final label = setting['label'] as String;
    switch (setting['type']) {
      case 'color':
        return AccentColorPickerButton(
          color: parseThemeColor(value)!.toARGB32(),
          label: label,
          onChanged: (color) =>
              _set(id, '#${color.toRadixString(16).padLeft(8, '0')}'),
        );
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value as bool,
          onChanged: (v) => _set(id, v),
        );
      case 'choice':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final choice in setting['choices'] as List)
                  ChoiceChip(
                    label: Text(choice as String),
                    selected: value == choice,
                    onSelected: (_) => _set(id, choice),
                  ),
              ],
            ),
          ],
        );
      case 'number':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label — ${(value as num).toStringAsFixed(2)}'),
            Slider(
              value: value.toDouble(),
              min: (setting['min'] as num).toDouble(),
              max: (setting['max'] as num).toDouble(),
              divisions: 20,
              onChanged: (v) => _set(id, v),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
