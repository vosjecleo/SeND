import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:mime/mime.dart';
import '../models/chat_models.dart';

/// Capture actual user paste data synchronously, before Flutter's hidden input
/// consumes it. Safari grants access to these File objects during the gesture;
/// a later navigator.clipboard.read() is not equivalent on iOS.
void Function() listenBrowserImagePaste({
  required bool Function() enabled,
  Object? Function()? contextKey,
  required void Function(List<AttachmentDraft>) onImages,
  required void Function(String) onError,
}) {
  var disposed = false;
  final listener = ((web.ClipboardEvent event) {
    if (!enabled()) return;
    final originalContext = contextKey?.call();
    final items = event.clipboardData?.items;
    if (items == null) return;
    final files = <web.File>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind == 'file' && item.type.startsWith('image/')) {
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
    }
    if (files.isEmpty) return; // Text/link paste remains the editor's job.
    event.preventDefault();
    event.stopImmediatePropagation();
    if (files.length > 20 ||
        files.fold<int>(0, (total, file) => total + file.size) >
            64 * 1024 * 1024) {
      onError('Paste at most 20 images, up to 64 MiB in total.');
      return;
    }
    () async {
      try {
        final drafts = <AttachmentDraft>[];
        for (final file in files) {
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          drafts.add(
            AttachmentDraft(
              bytes: bytes,
              name: file.name.isEmpty ? 'pasted-image.png' : file.name,
              mimeType:
                  lookupMimeType(file.name, headerBytes: bytes) ?? file.type,
              spoiler: false,
            ),
          );
        }
        if (!disposed && originalContext == contextKey?.call()) {
          onImages(drafts);
        }
      } catch (_) {
        if (!disposed) {
          onError(
            'Could not paste this image. Try attaching the original from Photos or Files.',
          );
        }
      }
    }();
  }).toJS;
  web.document.addEventListener('paste', listener, true.toJS);
  return () {
    disposed = true;
    web.document.removeEventListener('paste', listener, true.toJS);
  };
}
