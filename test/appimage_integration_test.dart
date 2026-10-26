import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/appimage_integration_native.dart';

void main() {
  test(
    'desktop entry uses actual AppImage and stable matching icon ID',
    () async {
      final root = await Directory.systemTemp.createTemp('send-desktop-test-');
      addTearDown(() => root.delete(recursive: true));
      final image = File('${root.path}/SeND with spaces.AppImage');
      await image.writeAsString('test');
      final icon = File('${root.path}/source.png');
      await icon.writeAsBytes([1, 2, 3]);
      final data = Directory('${root.path}/data');
      await installAppImageDesktopEntry(
        appImage: image,
        icon: icon,
        dataDirectory: data,
      );
      final entry = File(
        '${data.path}/applications/net.deltie.deltiecord.desktop',
      );
      final text = await entry.readAsString();
      expect(text, contains('Exec="${image.path}"'));
      expect(text, contains('Icon=net.deltie.deltiecord'));
      expect(text, contains('StartupWMClass=net.deltie.deltiecord'));
      expect(
        await File(
          '${data.path}/icons/hicolor/256x256/apps/net.deltie.deltiecord.png',
        ).readAsBytes(),
        [1, 2, 3],
      );
      final validation = await Process.run('desktop-file-validate', [
        entry.path,
      ]);
      expect(validation.exitCode, 0, reason: '${validation.stderr}');
    },
    skip: !Platform.isLinux,
  );
  test('launcher paths cannot introduce fields or field codes', () {
    expect(
      () => desktopExecArgument('/tmp/app\nExec=other'),
      throwsFormatException,
    );
    expect(desktopExecArgument('/tmp/100%.AppImage'), contains('100%%'));
    expect(desktopExecArgument('/tmp/a"b'), contains(r'\\"'));
  });
}
