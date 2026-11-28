import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/emoji_repository.dart';
import 'emoji_picker_dialog.dart';
import 'emoji_typography.dart';
import 'matrix_html_text.dart' show CustomEmojiImage, isUnicodeEmojiOnly;

// Keep the alias visible in clients that don't render the Matrix media link.
final _customStatusPrefix = RegExp(
  r'^\[:([A-Za-z0-9_+.-]{1,64}):\]\((mxc://(?:[A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(?::[0-9]{1,5})?/[A-Za-z0-9._~-]{1,128})\)(?=\s|$)',
);

CustomEmojiReference? customProfileStatusEmoji(String? prefix) {
  if (prefix == null) return null;
  final match = _customStatusPrefix.firstMatch(prefix);
  if (match == null || match.end != prefix.length) return null;
  final uri = Uri.tryParse(match[2]!);
  if (uri == null || uri.host.isEmpty || uri.toString().length > 200) {
    return null;
  }
  return CustomEmojiReference(id: uri, name: match[1]!);
}

/// Unicode stays plain text; custom emoji use a leading alias + MXC link.
({String? emoji, String text}) splitProfileStatus(String? value) {
  final status = value?.trim() ?? '';
  final match = _customStatusPrefix.firstMatch(status);
  if (match != null && customProfileStatusEmoji(match[0]) != null) {
    return (emoji: match[0], text: status.substring(match.end).trimLeft());
  }
  final first = status.characters.firstOrNull;
  if (first == null || !isUnicodeEmojiOnly(first)) {
    return (emoji: null, text: status);
  }
  final rest = status.substring(first.length);
  if (rest.isNotEmpty && rest == rest.trimLeft()) {
    return (emoji: null, text: status);
  }
  return (emoji: first, text: rest.trimLeft());
}

String joinProfileStatus(String? emoji, String text) =>
    [?emoji, if (text.trim().isNotEmpty) text.trim()].join(' ');

class ProfileStatusEmojiGlyph extends StatelessWidget {
  const ProfileStatusEmojiGlyph({
    required this.prefix,
    required this.backend,
    required this.size,
    super.key,
  });

  final String prefix;
  final ChatBackend? backend;
  final double size;

  @override
  Widget build(BuildContext context) {
    final custom = customProfileStatusEmoji(prefix);
    if (custom == null) {
      return Text(prefix, style: colourEmojiStyle(TextStyle(fontSize: size)));
    }
    final source = backend;
    if (source == null) return Text(custom.fallback);
    return Tooltip(
      message: custom.fallback,
      child: SizedBox.square(
        dimension: size,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: CustomEmojiImage(backend: source, emoji: custom, size: size),
        ),
      ),
    );
  }
}

class ProfileStatusField extends StatelessWidget {
  const ProfileStatusField({
    required this.backend,
    required this.controller,
    required this.emoji,
    required this.onEmojiChanged,
    this.enabled = true,
    this.onReset,
    this.autofocus = false,
    super.key,
  });

  final ChatBackend backend;
  final TextEditingController controller;
  final String? emoji;
  final ValueChanged<String?> onEmojiChanged;
  final VoidCallback? onReset;
  final bool enabled, autofocus;

  Future<void> _pick(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final picked = await showDialog<Object>(
      context: context,
      builder: (context) =>
          EmojiPickerDialog(backend: backend, removeSelection: emoji != null),
    );
    if (!context.mounted) return;
    if (picked == EmojiPickerAction.remove) onEmojiChanged(null);
    if (picked is EmojiEntry) {
      final custom = picked.customEmoji?.customEmoji;
      if (custom != null) {
        final prefix = '[${custom.fallback}](${custom.id})';
        if (customProfileStatusEmoji(prefix) != null) onEmojiChanged(prefix);
      } else if (picked.emoji.characters.length == 1) {
        onEmojiChanged(picked.emoji);
      }
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    enabled: enabled,
    maxLength: 120,
    maxLines: 1,
    decoration: InputDecoration(
      labelText: 'Status',
      hintText: 'What are you up to?',
      prefixIcon: IconButton(
        tooltip: emoji == null ? 'Choose status emoji' : 'Change status emoji',
        onPressed: enabled ? () => _pick(context) : null,
        icon: emoji == null
            ? const Icon(Icons.emoji_emotions_outlined)
            : ProfileStatusEmojiGlyph(
                prefix: emoji!,
                backend: backend,
                size: 20,
              ),
      ),
      suffixIcon: onReset == null
          ? null
          : IconButton(
              tooltip: 'Use general status',
              onPressed: enabled ? onReset : null,
              icon: const Icon(Icons.restart_alt),
            ),
    ),
  );
}

Future<void> showQuickProfileStatusEditor(
  BuildContext context,
  ChatBackend backend,
) => showDialog<void>(
  context: context,
  builder: (_) => _QuickProfileStatusEditor(backend: backend),
);

class _QuickProfileStatusEditor extends StatefulWidget {
  const _QuickProfileStatusEditor({required this.backend});
  final ChatBackend backend;

  @override
  State<_QuickProfileStatusEditor> createState() =>
      _QuickProfileStatusEditorState();
}

class _QuickProfileStatusEditorState extends State<_QuickProfileStatusEditor> {
  late final _initial = splitProfileStatus(widget.backend.profileStatusMessage);
  late final _text = TextEditingController(text: _initial.text);
  late String? _emoji = _initial.emoji;
  bool _saving = false, _failed = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.backend.updateOwnProfileFields(
        statusMessage: joinProfileStatus(_emoji, _text.text),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit status'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileStatusField(
            backend: widget.backend,
            controller: _text,
            emoji: _emoji,
            onEmojiChanged: (value) => setState(() => _emoji = value),
            autofocus: true,
            enabled: !_saving,
          ),
          if (_failed) const Text('Couldn’t save your status. Try again.'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
