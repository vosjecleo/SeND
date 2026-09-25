import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'update_checker.dart';

Future<String?> installedArtifactSuffix() async {
  if (Platform.isAndroid) {
    return switch (Abi.current()) {
      Abi.androidArm64 => '-android-arm64-v8a.apk',
      Abi.androidArm => '-android-armeabi-v7a.apk',
      Abi.androidX64 => '-android-x86_64.apk',
      _ => null,
    };
  }
  final directory = File(Platform.resolvedExecutable).parent;
  if (Platform.isWindows && Abi.current() == Abi.windowsX64) {
    return await File(p.join(directory.path, 'unins000.exe')).exists()
        ? '-windows-x64-setup.exe'
        : '-windows-x64-portable.zip';
  }
  if (Platform.isLinux && Abi.current() == Abi.linuxX64) {
    if (Platform.environment['APPIMAGE']?.isNotEmpty == true) {
      return '-linux-appimage-x86_64.AppImage';
    }
    final marker = File(p.join(directory.path, 'data', 'send-package'));
    if (await marker.exists()) {
      final type = (await marker.readAsString()).trim();
      if (type == 'deb') return '-linux-debian-amd64.deb';
      if (type == 'arch') return '-linux-arch-x86_64.pkg.tar.zst';
      if (type == 'appimage') return '-linux-appimage-x86_64.AppImage';
    }
    // Existing installations predate package markers. Query ownership, not the
    // distro: an Arch host may be running an AppImage or an unpacked preview.
    for (final query in [
      (
        'dpkg-query',
        ['-S', Platform.resolvedExecutable],
        '-linux-debian-amd64.deb',
      ),
      (
        'pacman',
        ['-Qo', Platform.resolvedExecutable],
        '-linux-arch-x86_64.pkg.tar.zst',
      ),
    ]) {
      try {
        final result = await Process.run(
          query.$1,
          query.$2,
        ).timeout(const Duration(seconds: 2));
        if (result.exitCode == 0) return query.$3;
      } catch (_) {
        /* Not installed or not a package-managed binary. */
      }
    }
  }
  return null; // Unknown/local builds use the downloads page; never guess.
}

/// User-initiated, interactive Inno upgrade. No silent elevation/forced exit.
/// TLS manifest + SHA-256 protect transfer integrity, not publisher signing.
Future<void> installWindowsUpdate(ReleaseArtifact artifact) async {
  if (!Platform.isWindows ||
      await installedArtifactSuffix() != '-windows-x64-setup.exe' ||
      !artifact.name.endsWith('-windows-x64-setup.exe') ||
      !RegExp(r'^[A-Za-z0-9+_.-]+$').hasMatch(artifact.name) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(artifact.sha256) ||
      artifact.size <= 0 ||
      artifact.size > 512 * 1024 * 1024) {
    throw StateError('This installation does not support installer updates.');
  }
  final temporary = await Directory.systemTemp.createTemp('send-update-');
  final file = File(p.join(temporary.path, artifact.name));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final deadline = Timer(
    const Duration(minutes: 5),
    () => client.close(force: true),
  );
  var launched = false;
  try {
    final request = await client
        .getUrl(artifact.url)
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw const HttpException('Installer download failed.');
    }
    var count = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        count += chunk.length;
        if (count > artifact.size) {
          throw const FormatException('Installer size mismatch.');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (count != artifact.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            artifact.sha256) {
      throw const FormatException(
        'Installer checksum mismatch. Nothing was installed.',
      );
    }
    await Process.start(file.path, [
      '/DIR=${File(Platform.resolvedExecutable).parent.path}',
      '/NORESTART',
    ], mode: ProcessStartMode.detached);
    launched = true;
  } finally {
    deadline.cancel();
    client.close(force: true);
    // The installer needs its downloaded file after this process returns.
    if (!launched) await temporary.delete(recursive: true);
  }
}
