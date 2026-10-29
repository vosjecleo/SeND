import 'platform_io.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'protected_file_codec.dart';

import 'package:path/path.dart' as path;

/// Creates an application-private directory and tightens desktop Unix modes.
///
/// Android/iOS application directories are sandboxed by the OS. Linux and
/// macOS need an explicit owner-only mode because the process umask is outside
/// SeND's control.
Future<void> ensurePrivateDirectory(Directory directory) async {
  await directory.create(recursive: true);
  if (Platform.isLinux || Platform.isMacOS) {
    final result = await Process.run('chmod', ['700', directory.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Could not secure private application directory',
        directory.path,
      );
    }
  }
}

/// Atomically replaces a private UTF-8 file where the host supports rename.
///
/// The temporary is owner-only before message text is written. Windows cannot
/// replace an existing file with `rename`, so it uses a same-directory backup
/// and restores it if the replacement fails.
Future<void> writePrivateTextFile(File target, String contents) =>
    writePrivateBytesFile(target, utf8.encode(contents));

Future<String> readPrivateTextFile(File file) async =>
    utf8.decode(await readPrivateBytesFile(file));

File _replacementBackup(File target) =>
    File('${target.path}.send-replacement-backup');
Future<bool> privateFileExists(File target) async {
  final backup = _replacementBackup(target);
  if (!await target.exists() && await backup.exists()) {
    await backup.rename(target.path);
  }
  return target.exists();
}

Future<Uint8List> readPrivateBytesFile(File file) async {
  await privateFileExists(file);
  final bytes = await file.readAsBytes();
  final codec = ProtectedFileCodec.instance;
  if (codec.encrypted(bytes)) {
    final decoded = await codec.open(bytes, path.basename(file.path));
    final backup = _replacementBackup(file);
    if (await backup.exists()) await backup.delete();
    return decoded;
  }
  // Rewrite legacy data atomically only after key storage and encryption work.
  await writePrivateBytesFile(file, bytes);
  return bytes;
}

Future<void> writePrivateBytesFile(File target, List<int> contents) async {
  await ensurePrivateDirectory(target.parent);
  final codec = ProtectedFileCodec.instance;
  await privateFileExists(target);
  final previous = await target.exists() ? await target.readAsBytes() : null;
  final requireExisting = previous != null && codec.encrypted(previous);
  final oldBackup = _replacementBackup(target);
  if (await oldBackup.exists()) {
    if (requireExisting) {
      await codec.open(previous, path.basename(target.path));
    }
    await oldBackup.delete();
  }
  final protected = await codec.seal(
    contents,
    path.basename(target.path),
    requireExisting: requireExisting,
  );
  final random = Random.secure();
  final suffix = List.generate(
    12,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final temporary = File(
    path.join(target.parent.path, '.${path.basename(target.path)}.$suffix.tmp'),
  );
  File? backup;
  try {
    await temporary.create(exclusive: true);
    await _secureFile(temporary);
    await temporary.writeAsBytes(protected, flush: true);
    if (Platform.isWindows && await target.exists()) {
      backup = _replacementBackup(target);
      await target.rename(backup.path);
    }
    await temporary.rename(target.path);
    await _secureFile(target);
    if (backup != null && await backup.exists()) await backup.delete();
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    if (backup != null && await backup.exists() && !await target.exists()) {
      await backup.rename(target.path);
    }
    rethrow;
  }
}

Future<void> deletePrivateFile(File? file) async {
  if (file == null) return;
  if (await file.exists()) await file.delete();
  final backup = _replacementBackup(file);
  if (await backup.exists()) await backup.delete();
}

Future<void> _secureFile(File file) async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final result = await Process.run('chmod', ['600', file.path]);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Could not secure private application file',
      file.path,
    );
  }
}
