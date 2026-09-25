import 'dart:io';

Future<String?> activitySocketIdentity(String target) async {
  if (await FileSystemEntity.type(target, followLinks: false) !=
      FileSystemEntityType.unixDomainSock) {
    return null;
  }
  final result = await Process.run('stat', ['-c', '%u:%i', '--', target]);
  return result.exitCode == 0 ? result.stdout.toString().trim() : null;
}

/// Recover only an owned, unchanged Unix socket that explicitly refuses a
/// connection. Timeouts, permission failures, symlinks and live sockets stay put.
Future<bool> prepareActivitySocket(String path, String runtime) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return true;
  if (type != FileSystemEntityType.unixDomainSock) return false;
  Future<String?> identity(String target) async {
    final result = await Process.run('stat', ['-c', '%u:%i', '--', target]);
    return result.exitCode == 0 ? result.stdout.toString().trim() : null;
  }

  try {
    final before = await identity(path);
    final owner = await identity(runtime);
    final uid = await Process.run('id', ['-u']);
    if (before == null ||
        owner == null ||
        uid.exitCode != 0 ||
        before.split(':').first != uid.stdout.toString().trim() ||
        owner.split(':').first != before.split(':').first) {
      return false;
    }
    try {
      final socket = await Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 300),
      );
      socket.destroy();
      return false;
    } on SocketException catch (error) {
      if (error.osError?.errorCode != 111) {
        return false; // ECONNREFUSED on Linux
      }
    }
    if (await identity(path) != before ||
        await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.unixDomainSock) {
      return false;
    }
    await File(path).delete();
    return true;
  } catch (_) {
    return false;
  }
}
