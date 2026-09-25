import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/update_checker.dart';
import 'package:deltiecord/services/update_installation.dart';

void main() {
  final hash = List.filled(64, 'a').join();
  Map<String, Object> artifact(
    String suffix, {
    String prefix = 'SeND',
    int build = 109,
  }) => {'name': '$prefix-0.9.35+$build$suffix', 'sha256': hash, 'size': 1000};
  ReleaseCheckResult parse(List<Object> files) => parseReleaseManifest(
    jsonEncode({
      'version': '0.9.35',
      'build': 109,
      'platforms': {
        'all': {'latest': files},
      },
    }),
    currentVersion: '0.9.35',
    currentBuild: 108,
  );

  test('selects exact ABI and package; no fallback to another binary', () {
    const suffixes = [
      '-android-arm64-v8a.apk',
      '-android-armeabi-v7a.apk',
      '-android-x86_64.apk',
      '-windows-x64-setup.exe',
      '-windows-x64-portable.zip',
      '-linux-arch-x86_64.pkg.tar.zst',
      '-linux-debian-amd64.deb',
      '-linux-appimage-x86_64.AppImage',
    ];
    final result = parse(suffixes.map(artifact).toList());
    expect(result.updateAvailable, isTrue);
    for (final suffix in suffixes) {
      final selected = result.artifactFor(suffix)!;
      expect(selected.name, 'SeND-0.9.35+109$suffix');
      expect(selected.url.host, 'deltie.net');
      expect(selected.url.pathSegments, ['SeND', selected.name]);
    }
    expect(result.artifactFor(null), isNull);
    expect(result.artifactFor('-macos.zip'), isNull);
  });
  test(
    'accepts legacy artifacts; rejects mismatched release and unsafe metadata',
    () {
      final result = parse([
        artifact('-android-arm64-v8a.apk', prefix: 'deltiecord'),
        artifact('-windows-x64-setup.exe', build: 108),
        {...artifact('-windows-x64-setup.exe'), 'name': '../setup.exe'},
        {...artifact('-windows-x64-setup.exe'), 'sha256': 'invalid'},
        {...artifact('-windows-x64-setup.exe'), 'size': -1},
        {...artifact('-windows-x64-setup.exe'), 'size': 2 * 1024 * 1024 * 1024},
      ]);
      expect(result.artifacts, hasLength(1));
      expect(result.artifactFor('-windows-x64-setup.exe'), isNull);
      expect(result.artifacts.single.name, startsWith('deltiecord-'));
    },
  );
  test('stable channel never downloads latest channel artifacts', () {
    final result = parseReleaseManifest(
      jsonEncode({
        'version': '0.9.35',
        'build': 109,
        'platforms': {
          'android': {
            'latest': [artifact('-android-arm64-v8a.apk')],
            'stable': [artifact('-android-arm64-v8a.apk', build: 108)],
          },
        },
      }),
      currentVersion: '0.9.35',
      currentBuild: 107,
      stableOnly: true,
    );
    expect(result.build, 108);
    expect(result.artifacts.single.name, contains('+108-'));
  });
  test('installer execution refuses non-Windows hosts', () async {
    if (Platform.isWindows) return;
    await expectLater(
      installWindowsUpdate(
        ReleaseArtifact('SeND-0.9.35+109-windows-x64-setup.exe', hash, 1000),
      ),
      throwsStateError,
    );
  });
  test('rename preserves session, storage and installer identity', () {
    for (final path in ['native', 'web']) {
      expect(
        File('lib/matrix/matrix_client_factory_$path.dart').readAsStringSync(),
        contains("'Deltiecord', // Persistent SDK client ID"),
      );
    }
    final resource = File('windows/runner/Runner.rc').readAsStringSync();
    expect(resource, contains('"ProductName", "Deltiecord"'));
    expect(resource, contains('"CompanyName", "Deltiecord contributors"'));
    expect(resource, contains('"FileDescription", "SeND Matrix client"'));
    final installer = File(
      'packaging/windows/deltiecord.iss',
    ).readAsStringSync();
    expect(
      installer,
      contains('AppId={{2E5E8DB4-F62B-4E91-B4C4-2CA41EDCC91F}'),
    );
    expect(installer, contains('AppName=SeND'));
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:label="SeND"'),
    );
    expect(
      File('web/manifest.json').readAsStringSync(),
      contains('"name": "SeND"'),
    );
  });
}
