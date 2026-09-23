import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

@JS('deltieFetchMedia')
external JSPromise<JSUint8Array> _fetch(
  JSString uri,
  JSString token,
  JSNumber maximumBytes,
);
Future<Uint8List> downloadBrowserMedia(
  Uri uri,
  String token,
  int maximumBytes,
) async => (await _fetch(
  uri.toString().toJS,
  token.toJS,
  maximumBytes.toJS,
).toDart).toDart;

/// Decryption stays in the Matrix SDK. Only the browser's opaque Blob handle
/// reaches the video element: never a credential-bearing Matrix URL.
Uri createBrowserMediaUrl(Uint8List bytes, String mimeType) => Uri.parse(
  web.URL.createObjectURL(
    web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType)),
  ),
);
void releaseBrowserMediaUrl(Uri uri) {
  if (uri.scheme == 'blob') web.URL.revokeObjectURL(uri.toString());
}
