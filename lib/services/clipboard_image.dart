import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:super_clipboard/super_clipboard.dart';

/// Prefer animated/original formats over the OS's flattened PNG rendition.
final clipboardImageFormats = [
  Formats.gif,
  Formats.webp,
  Formats.png,
  Formats.jpeg,
];

/// Start the image read directly in the user's paste gesture. Flutter's
/// built-in text paste alone cannot consume an iOS screenshot clipboard item.
Future<void> pasteComposerClipboard({
  required TextEditingController controller,
  required Future<bool> Function() pasteImage,
  required bool Function() isCurrent,
}) async {
  try {
    if (await pasteImage()) return;
  } catch (_) {
    // A browser may deny image access while still allowing ordinary text.
  }
  if (!isCurrent()) return;
  final ClipboardData? data;
  try {
    data = await Clipboard.getData(Clipboard.kTextPlain);
  } catch (_) {
    return;
  }
  if (!isCurrent() || data?.text == null) return;
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : start;
  controller.value = TextEditingValue(
    text: value.text.replaceRange(start, end, data!.text!),
    selection: TextSelection.collapsed(offset: start + data.text!.length),
  );
}

Future<Uint8List?> readClipboardImage() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) return null;
  final reader = await clipboard.read();
  for (final format in clipboardImageFormats) {
    if (!reader.canProvide(format)) continue;
    final completed = Completer<Uint8List?>();
    final progress = reader.getFile(
      format,
      (file) async {
        try {
          final bytes = await file.readAll();
          if (!completed.isCompleted) completed.complete(bytes);
        } catch (_) {
          if (!completed.isCompleted) completed.complete(null);
        }
      },
      onError: (_) {
        if (!completed.isCompleted) completed.complete(null);
      },
    );
    if (progress == null) continue;
    final bytes = await completed.future;
    if (bytes != null && bytes.isNotEmpty) return bytes;
  }
  return null;
}
