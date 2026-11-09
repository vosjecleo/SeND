import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:mime/mime.dart';
import '../models/chat_models.dart';
import 'attachment_admission.dart';

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
    final data = event.clipboardData;
    if (data == null) return;
    final items = data.items;
    final files = <web.File>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.kind == 'file' &&
          (item.type.isEmpty || item.type.startsWith('image/'))) {
        final file = item.getAsFile();
        if (file != null) files.add(file);
      }
    }
    // Safari can expose clipboard files without equivalent DataTransfer items.
    if (files.isEmpty) {
      for (var i = 0; i < data.files.length; i++) {
        final file = data.files.item(i);
        if (file != null &&
            (file.type.isEmpty || file.type.startsWith('image/'))) {
          files.add(file);
        }
      }
    }
    if (files.isEmpty) return; // Text/link paste remains the editor's job.
    event.preventDefault();
    event.stopImmediatePropagation();
    if (files.length > 20 ||
        files.fold<int>(0, (total, file) => total + file.size) >
            attachmentReadBudget) {
      onError('Paste up to 20 images (512 MiB to edit safely).');
      return;
    }
    () async {
      try {
        final drafts = <AttachmentDraft>[];
        for (final file in files) {
          final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
          final mime =
              lookupMimeType(file.name, headerBytes: bytes) ?? file.type;
          if (!mime.startsWith('image/')) continue;
          drafts.add(
            AttachmentDraft(
              bytes: bytes,
              name: file.name.isEmpty ? 'pasted-image.png' : file.name,
              mimeType: mime,
              spoiler: false,
            ),
          );
        }
        if (!disposed && originalContext == contextKey?.call()) {
          onImages(drafts);
        }
      } catch (_) {
        if (!disposed) {
          onError('Couldn\'t paste the image. Attach it from Photos or Files.');
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
