import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:mime/mime.dart';
import '../models/chat_models.dart';

/// Read user-selected File objects directly; no blob URL fetch/CSP exception.
/// Call from the button handler, before awaiting route dismissal on Safari.
Future<List<AttachmentDraft>> pickBrowserAttachments({
  String accept = '',
  bool camera = false,
}) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..multiple = !camera;
  if (camera) input.setAttribute('capture', 'environment');
  input.style.display = 'none';
  web.document.body!.append(input);
  final chosen = Completer<void>();
  void finish(web.Event _) {
    if (!chosen.isCompleted) chosen.complete();
  }

  final listener = finish.toJS;
  input.addEventListener('change', listener);
  input.addEventListener('cancel', listener);
  try {
    input.click();
    await chosen.future;
    final files = input.files;
    if (files == null || files.length == 0) return const [];
    if (files.length > 20) throw StateError('Choose at most 20 files.');
    var total = 0;
    for (var i = 0; i < files.length; i++) {
      total += files.item(i)!.size;
    }
    if (total > 64 * 1024 * 1024) {
      throw StateError('Choose at most 64 MiB per selection.');
    }
    final drafts = <AttachmentDraft>[];
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i)!;
      final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
      drafts.add(
        AttachmentDraft(
          bytes: bytes,
          name: file.name,
          mimeType:
              lookupMimeType(file.name, headerBytes: bytes) ??
              (file.type.isEmpty ? 'application/octet-stream' : file.type),
          spoiler: false,
        ),
      );
    }
    return drafts;
  } finally {
    input.removeEventListener('change', listener);
    input.removeEventListener('cancel', listener);
    input.remove();
  }
}
