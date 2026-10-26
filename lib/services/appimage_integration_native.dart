import 'dart:io';
import 'package:path/path.dart' as p;

bool get canIntegrateAppImage =>
    Platform.isLinux && (Platform.environment['APPIMAGE']?.isNotEmpty ?? false);

String desktopExecArgument(String path) {
  if (path.contains(RegExp(r'[\r\n\x00]'))) {
    throw const FormatException('Unsupported AppImage path.');
  }
  return '"${path.replaceAll(r'\', r'\\\\').replaceAll('"', r'\\"').replaceAll(r'$', r'\\$').replaceAll('`', r'\\`').replaceAll('%', '%%')}"';
}

Future<void> installAppImageDesktopEntry({
  required File appImage,
  required File icon,
  required Directory dataDirectory,
}) async {
  final path = await appImage.resolveSymbolicLinks();
  final quoted = desktopExecArgument(path);
  final applications = Directory(p.join(dataDirectory.path, 'applications'));
  final icons = Directory(
    p.join(dataDirectory.path, 'icons', 'hicolor', '256x256', 'apps'),
  );
  await applications.create(recursive: true);
  await icons.create(recursive: true);
  await icon.copy(p.join(icons.path, 'net.deltie.deltiecord.png'));
  final desktop = File(
    p.join(applications.path, 'net.deltie.deltiecord.desktop'),
  );
  await desktop.writeAsString(
    '[Desktop Entry]\nType=Application\nName=SeND\n'
    'Comment=Matrix messaging\nExec=$quoted\nIcon=net.deltie.deltiecord\n'
    'Terminal=false\nCategories=Network;Chat;InstantMessaging;\n'
    'StartupNotify=true\nStartupWMClass=net.deltie.deltiecord\n',
    flush: true,
  );
}

Future<void> integrateAppImage() async {
  if (!canIntegrateAppImage) {
    throw UnsupportedError('Launch the AppImage to integrate it.');
  }
  final data = Platform.environment['XDG_DATA_HOME'];
  final home = Platform.environment['HOME'];
  if ((data == null || data.isEmpty) && (home == null || home.isEmpty)) {
    throw StateError('Home directory unavailable.');
  }
  final root = Platform.environment['APPDIR'];
  final prefix = root != null && root.isNotEmpty
      ? p.join(root, 'usr')
      : File(Platform.resolvedExecutable).parent.parent.parent.path;
  await installAppImageDesktopEntry(
    appImage: File(Platform.environment['APPIMAGE']!),
    icon: File(
      p.join(
        prefix,
        'share',
        'icons',
        'hicolor',
        '256x256',
        'apps',
        'net.deltie.deltiecord.png',
      ),
    ),
    dataDirectory: Directory(
      data?.isNotEmpty == true ? data! : p.join(home!, '.local', 'share'),
    ),
  );
}
