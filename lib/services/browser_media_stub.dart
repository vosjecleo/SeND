import 'dart:typed_data';

Uri createBrowserMediaUrl(Uint8List bytes, String mimeType) =>
    throw UnsupportedError('Blob URLs require a browser.');
void releaseBrowserMediaUrl(Uri uri) {}
Future<Uint8List> downloadBrowserMedia(
  Uri uri,
  String token,
  int maximumBytes,
) => Future.error(UnsupportedError('Browser only'));
