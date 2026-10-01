import '../models/chat_models.dart';

void Function() listenBrowserImagePaste({
  required bool Function() enabled,
  Object? Function()? contextKey,
  required void Function(List<AttachmentDraft>) onImages,
  required void Function(String) onError,
}) => () {};
