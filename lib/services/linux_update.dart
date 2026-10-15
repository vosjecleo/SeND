import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'appimage_delta.dart';
import 'private_file_store.dart';
import 'socks_proxy.dart';
import 'update_checker.dart';
import 'update_progress.dart';

export 'update_progress.dart';

typedef UpdateCommand =
    Future<int> Function(
      String executable,
      List<String> arguments,
      String directory,
    );

Future<int> runUpdateCommand(
  String executable,
  List<String> arguments,
  String directory,
) async {
  final environment = Map<String, String>.of(Platform.environment)
    ..removeWhere(
      (key, _) => const [
        'http_proxy',
        'https_proxy',
        'all_proxy',
        'no_proxy',
      ].contains(key.toLowerCase()),
    );
  environment['DEBIAN_FRONTEND'] = 'noninteractive';
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    environment: environment,
    includeParentEnvironment: false,
  );
  final output = process.stdout.drain<void>();
  final errors = process.stderr.drain<void>();
  // No stdin password collection or terminal fallback. pkexec must use the
  // desktop authentication agent. APT/pacman output may contain local paths.
  await process.stdin.close();
  final timer = Timer(const Duration(minutes: 15), () => process.kill());
  try {
    final code = await process.exitCode;
    await Future.wait([output, errors]);
    return code;
  } finally {
    timer.cancel();
  }
}

void validateUpdateArtifact(ReleaseArtifact artifact) {
  if (!RegExp(r'^[A-Za-z0-9+_.-]{1,180}$').hasMatch(artifact.name) ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(artifact.sha256) ||
      artifact.size < 1 ||
      artifact.size > 512 * 1024 * 1024) {
    throw const FormatException('Invalid update metadata.');
  }
}

Future<void> verifyUpdateFile(File file, ReleaseArtifact artifact) async {
  validateUpdateArtifact(artifact);
  if (await file.length() != artifact.size ||
      (await sha256.bind(file.openRead()).first).toString() !=
          artifact.sha256) {
    throw const FormatException(
      'Update verification failed. Nothing was installed.',
    );
  }
}

Future<void> downloadUpdateFile(
  HttpClient client,
  ReleaseArtifact artifact,
  File destination, {
  void Function(UpdateProgress)? progress,
}) async {
  validateUpdateArtifact(artifact);
  final request = await client
      .getUrl(artifact.url)
      .timeout(const Duration(seconds: 15));
  request.followRedirects = false;
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  final response = await request.close().timeout(const Duration(seconds: 20));
  if (response.statusCode != 200 ||
      (response.contentLength >= 0 &&
          response.contentLength != artifact.size)) {
    throw const HttpException('Update download failed.');
  }
  var count = 0;
  final sink = destination.openWrite();
  try {
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      count += chunk.length;
      if (count > artifact.size) {
        throw const FormatException('Update is too large.');
      }
      sink.add(chunk);
      await sink.flush();
      progress?.call(
        UpdateProgress('Downloading update', count / artifact.size),
      );
    }
  } finally {
    await sink.close();
  }
  progress?.call(const UpdateProgress('Verifying update'));
  await verifyUpdateFile(destination, artifact);
}

/// No shell interpolation, distro guessing or whole-system upgrades.
List<String> linuxPackageInstallArguments(String suffix, String path) =>
    switch (suffix) {
      '-linux-debian-amd64.deb' => [
        '--disable-internal-agent',
        '/usr/bin/apt-get',
        '-y',
        '--no-remove',
        'install',
        '--',
        path,
      ],
      '-linux-arch-x86_64.pkg.tar.zst' => [
        '--disable-internal-agent',
        '/usr/bin/pacman',
        '-U',
        '--noconfirm',
        '--needed',
        '--',
        path,
      ],
      _ => throw UnsupportedError('This package cannot be installed in SeND.'),
    };

Future<void> fetchLinuxUpdatePayload(
  HttpClient client,
  ReleaseArtifact artifact,
  File file, {
  Future<void> Function()? delta,
  void Function(UpdateProgress)? progress,
}) async {
  if (delta != null) {
    try {
      progress?.call(const UpdateProgress('Reusing existing AppImage data'));
      await delta();
      await verifyUpdateFile(file, artifact);
      return;
    } catch (_) {
      final partial = File('${file.path}.part');
      if (await partial.exists()) await partial.delete();
      progress?.call(
        const UpdateProgress(
          'Delta update unavailable. Downloading the full update',
        ),
      );
    }
  }
  await downloadUpdateFile(client, artifact, file, progress: progress);
}

class PreparedLinuxUpdate {
  PreparedLinuxUpdate(
    this.directory,
    this.file,
    this.artifact,
    this.suffix, {
    this.original,
    this.originalHash,
    UpdateCommand? command,
  }) : command = command ?? runUpdateCommand;
  final Directory directory;
  final File file;
  final ReleaseArtifact artifact;
  final String suffix;
  final File? original;
  final String? originalHash;
  final UpdateCommand command;
  bool get isAppImage => original != null;
  bool _installed = false;
  bool get installed => _installed;
  String? backupPath;

  Future<void> install() async {
    if (_installed) return;
    await verifyUpdateFile(file, artifact);
    if (isAppImage) {
      final current = original!;
      if (await FileSystemEntity.type(current.path, followLinks: false) !=
              FileSystemEntityType.file ||
          (await sha256.bind(current.openRead()).first).toString() !=
              originalHash) {
        throw StateError(
          'The installed AppImage changed. Check for updates again.',
        );
      }
      final permissions = (await current.stat()).mode & 511;
      final backup = File(p.join(directory.path, 'previous.AppImage'));
      await current.copy(backup.path);
      if (await command('/usr/bin/chmod', [
            (permissions | 64).toRadixString(8),
            file.path,
            backup.path,
          ], directory.path) !=
          0) {
        throw StateError('Could not make the update executable.');
      }
      // Staging is in the original directory, so POSIX rename replaces the
      // image atomically. The running mount keeps its existing inode.
      final saved = p.join(
        current.parent.path,
        '.${p.basename(current.path)}.send-previous',
      );
      await backup.rename(saved);
      await file.rename(current.path);
      backupPath = saved;
    } else {
      if (SocksProxy.blockDirectTraffic) {
        throw StateError(
          'Package managers may use direct network connections. Allow direct traffic or update manually.',
        );
      }
      final code = await command(
        '/usr/bin/pkexec',
        linuxPackageInstallArguments(suffix, file.path),
        directory.path,
      );
      if (code == 126 || code == 127) {
        throw StateError(
          'Installation was cancelled or no desktop authentication agent is available.',
        );
      }
      if (code != 0) {
        throw StateError(
          'The package manager could not finish the update. Check its lock, dependencies and package-signature policy, then retry.',
        );
      }
    }
    _installed = true;
    try {
      await directory.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> restart() async {
    if (!_installed) await install();
    await Process.start(
      isAppImage ? original!.path : '/usr/bin/deltiecord',
      [],
      mode: ProcessStartMode.detached,
      environment: const {
        'APPIMAGE': '',
        'APPDIR': '',
        'ARGV0': '',
        'LD_LIBRARY_PATH': '',
        'LD_PRELOAD': '',
      },
    );
    exit(0);
  }

  Future<void> discard() async {
    if (!_installed && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

Future<PreparedLinuxUpdate> prepareLinuxUpdate(
  ReleaseArtifact artifact, {
  required String installedSuffix,
  ReleaseArtifact? control,
  void Function(UpdateProgress)? progress,
}) async {
  if (!Platform.isLinux ||
      Abi.current() != Abi.linuxX64 ||
      !artifact.name.endsWith(installedSuffix)) {
    throw UnsupportedError('This installation cannot use this update.');
  }
  validateUpdateArtifact(artifact);
  final appImage = installedSuffix == '-linux-appimage-x86_64.AppImage';
  if (!appImage) linuxPackageInstallArguments(installedSuffix, 'package');
  File? original;
  String? originalHash;
  if (appImage) {
    final path = Platform.environment['APPIMAGE'];
    if (path == null || path.isEmpty) {
      throw StateError(
        'Launch the AppImage normally to update it. Extracted copies need a manual download.',
      );
    }
    original = File(await File(path).resolveSymbolicLinks());
    originalHash = (await sha256.bind(original.openRead()).first).toString();
  }
  final directory = await (original?.parent ?? Directory.systemTemp).createTemp(
    '.send-update-',
  );
  await ensurePrivateDirectory(directory);
  final file = File(p.join(directory.path, artifact.name));
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final timer = Timer(
    const Duration(minutes: 10),
    () => client.close(force: true),
  );
  try {
    final helper = File(
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'updater',
        'zsync',
      ),
    );
    final useDelta =
        appImage &&
        control != null &&
        control.name == '${artifact.name}.zsync' &&
        control.size <= 16 * 1024 * 1024 &&
        await helper.exists();
    await fetchLinuxUpdatePayload(
      client,
      artifact,
      file,
      progress: progress,
      delta: !useDelta
          ? null
          : () => applyAppImageDelta(
              client: client,
              artifact: artifact,
              control: control,
              original: original!,
              destination: file,
              helper: helper,
              progress: progress,
            ),
    );
    return PreparedLinuxUpdate(
      directory,
      file,
      artifact,
      installedSuffix,
      original: original,
      originalHash: originalHash,
    );
  } catch (_) {
    await directory.delete(recursive: true);
    rethrow;
  } finally {
    timer.cancel();
    client.close(force: true);
  }
}
