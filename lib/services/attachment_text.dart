import 'package:matrix/matrix.dart';

/// Matrix requires a body for files even without a caption. Reply/edit fallback
/// markup is transport metadata, not user-authored caption text.
({String name, String? caption}) attachmentText(Event event) {
  final raw = event.content['body'];
  final body = raw is String && raw.isNotEmpty
      ? event.calcUnlocalizedBody(hideReply: true, hideEdit: true).trim()
      : '';
  final filename = event.content['filename'];
  final name = filename is String && filename.trim().isNotEmpty
      ? filename
      : body;
  return (
    name: name,
    caption: body.isNotEmpty && body != name.trim() ? body : null,
  );
}
