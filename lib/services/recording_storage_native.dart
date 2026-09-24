import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'private_file_store.dart';

Future<String> createRecordingPath(String extension) async {
  final root = Directory(
    '${(await getTemporaryDirectory()).path}/voice-drafts',
  );
  await ensurePrivateDirectory(root);
  final directory = await root.createTemp('recording-');
  await ensurePrivateDirectory(directory);
  return '${directory.path}/voice.$extension';
}

Future<Uint8List> readRecording(String path, int limit) async {
  final file = File(path);
  final length = await file.length();
  if (length == 0 || length > limit) throw StateError('Recording size limit');
  return file.readAsBytes();
}

Future<void> deleteRecording(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
  // Only remove the exact private directory allocated for this recording.
  if (await file.parent.exists()) await file.parent.delete();
}
