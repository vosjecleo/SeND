import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

/// Prefer animated/original formats over the OS's flattened PNG rendition.
final clipboardImageFormats = [
  Formats.gif,
  Formats.webp,
  Formats.png,
  Formats.jpeg,
];

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
