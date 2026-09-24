import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<String> createRecordingPath(String extension) async => '';
Future<Uint8List> readRecording(String path, int limit) async {
  if (!path.startsWith('blob:')) throw StateError('Invalid recording');
  final response = await web.window.fetch(path.toJS).toDart;
  final blob = await response.blob().toDart;
  if (blob.size == 0 || blob.size > limit) {
    throw StateError('Recording size limit');
  }
  return (await blob.arrayBuffer().toDart).toDart.asUint8List();
}

Future<void> deleteRecording(String path) async {
  if (path.startsWith('blob:')) web.URL.revokeObjectURL(path);
}
