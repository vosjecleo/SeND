import 'package:deltiecord/services/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official release replaces a preview without offering older builds', () {
    ReleaseCheckResult check(int build, {bool preview = true}) =>
        parseReleaseManifest(
          '{"version":"0.9.42","build":$build}',
          currentVersion: '0.9.42',
          currentBuild: 134,
          currentIsPreview: preview,
        );
    expect(check(134).updateAvailable, isTrue);
    expect(check(135).updateAvailable, isTrue);
    expect(check(133).updateAvailable, isFalse);
    expect(check(134, preview: false).updateAvailable, isFalse);
  });
  test('release manifest compares version and build independently', () {
    final newerBuild = parseReleaseManifest(
      '{"version":"0.9.19","build":65}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );
    final newerVersion = parseReleaseManifest(
      '{"version":"0.10.0","build":1}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );
    final older = parseReleaseManifest(
      '{"version":"0.9.18","build":999}',
      currentVersion: '0.9.19',
      currentBuild: 64,
    );

    expect(newerBuild.updateAvailable, isTrue);
    expect(newerVersion.updateAvailable, isTrue);
    expect(older.updateAvailable, isFalse);
  });

  test('release manifest rejects malformed and unreasonable metadata', () {
    expect(
      () => parseReleaseManifest(
        '{"version":"latest","build":64}',
        currentVersion: '0.9.19',
        currentBuild: 64,
      ),
      throwsFormatException,
    );
    expect(
      () => parseReleaseManifest(
        '{"version":"0.9.19","build":-1}',
        currentVersion: '0.9.19',
        currentBuild: 64,
      ),
      throwsFormatException,
    );
  });

  test('startup checks infer only the stable channel from artifacts', () {
    final result = parseReleaseManifest(
      '''
      {
        "version":"0.9.24",
        "build":76,
        "release":"latest",
        "platforms":{
          "android":{"stable":[
            {"name":"deltiecord-0.9.23+74-android-arm64-v8a.apk"}
          ]}
        }
      }
      ''',
      currentVersion: '0.9.23',
      currentBuild: 74,
      stableOnly: true,
    );

    expect(result.version, '0.9.23');
    expect(result.build, 74);
    expect(result.updateAvailable, isFalse);
  });
}
