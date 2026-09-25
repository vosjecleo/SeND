import 'dart:convert';
import 'platform_io.dart';

import 'bounded_http.dart';

const deltiecordReleasesPage = 'https://deltie.net/SeND/';
const _releaseManifestUrl = 'https://deltie.net/SeND/releases.json';

/// A bounded check against SeND's release manifest.
///
/// Startup invokes it only after the signed-in UI is usable, and Settings also
/// exposes an explicit retry. In either case release-site failure is isolated
/// from Matrix session startup.
class UpdateChecker {
  UpdateChecker({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  Future<ReleaseCheckResult> check({
    required String currentVersion,
    required int currentBuild,
    bool stableOnly = false,
  }) async {
    final request = await _client
        .getUrl(Uri.parse(_releaseManifestUrl))
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException(
        'Release server returned HTTP ${response.statusCode}.',
      );
    }
    if (!hasContentType(response, const ['application/json', 'text/json'])) {
      await response.drain<void>();
      throw const FormatException(
        'Release server returned an unexpected file.',
      );
    }
    final bytes = await readBoundedResponse(
      response,
      maximumBytes: 1024 * 1024,
      inactivityTimeout: const Duration(seconds: 8),
    );
    return parseReleaseManifest(
      utf8.decode(bytes),
      currentVersion: currentVersion,
      currentBuild: currentBuild,
      stableOnly: stableOnly,
    );
  }

  void close() => _client.close(force: true);
}

class ReleaseCheckResult {
  const ReleaseCheckResult({
    required this.version,
    required this.build,
    required this.updateAvailable,
    this.artifacts = const [],
  });

  final String version;
  final int build;
  final bool updateAvailable;
  final List<ReleaseArtifact> artifacts;

  ReleaseArtifact? artifactFor(String? suffix) {
    if (suffix == null) return null;
    for (final artifact in artifacts) {
      if (artifact.name.endsWith(suffix)) return artifact;
    }
    return null;
  }
}

/// Artifact URLs are derived from trusted hosting, never supplied by metadata.
class ReleaseArtifact {
  const ReleaseArtifact(this.name, this.sha256, this.size);
  final String name, sha256;
  final int size;
  Uri get url =>
      Uri.parse(deltiecordReleasesPage).resolve(Uri.encodeComponent(name));
}

ReleaseCheckResult parseReleaseManifest(
  String source, {
  required String currentVersion,
  required int currentBuild,
  bool stableOnly = false,
}) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid release manifest.');
  }
  var version = decoded['version'];
  var buildValue = decoded['build'];
  if (stableOnly) {
    version = decoded['stable_version'];
    buildValue = decoded['stable_build'];
    if (version == null || buildValue == null) {
      final inferred = _inferStableRelease(decoded);
      version = inferred?.$1;
      buildValue = inferred?.$2;
    }
  }
  final build = buildValue is int
      ? buildValue
      : int.tryParse(buildValue?.toString() ?? '');
  if (version is! String ||
      version.length > 32 ||
      !_versionPattern.hasMatch(version) ||
      build == null ||
      build < 0) {
    throw const FormatException('Invalid release version metadata.');
  }
  final comparison = compareVersions(version, currentVersion);
  final artifacts = <ReleaseArtifact>[];
  final platforms = decoded['platforms'];
  if (platforms is Map) {
    for (final platform in platforms.values) {
      final files = platform is Map
          ? platform[stableOnly ? 'stable' : 'latest']
          : null;
      if (files is! List) continue;
      for (final file in files) {
        if (file is! Map) continue;
        final name = file['name'], hash = file['sha256'], size = file['size'];
        if (name is! String || hash is! String || size is! int) continue;
        if (!RegExp(r'^[A-Za-z0-9+_.-]{1,180}$').hasMatch(name) ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
            size <= 0 ||
            size > 1024 * 1024 * 1024) {
          continue;
        }
        final match = _artifactVersionPattern.firstMatch(name);
        if (match?.group(1) != version ||
            int.tryParse(match?.group(2) ?? '') != build) {
          continue;
        }
        artifacts.add(ReleaseArtifact(name, hash.toLowerCase(), size));
      }
    }
  }
  return ReleaseCheckResult(
    version: version,
    build: build,
    artifacts: List.unmodifiable(artifacts),
    updateAvailable:
        comparison > 0 || (comparison == 0 && build > currentBuild),
  );
}

(String, int)? _inferStableRelease(Map<String, dynamic> manifest) {
  final platforms = manifest['platforms'];
  if (platforms is! Map) return null;
  final candidates = <(String, int)>[];
  for (final platform in platforms.values) {
    if (platform is! Map) continue;
    final stable = platform['stable'];
    if (stable is! List) continue;
    for (final artifact in stable) {
      if (artifact is! Map) continue;
      final name = artifact['name']?.toString();
      if (name == null) continue;
      final match = _artifactVersionPattern.firstMatch(name);
      final version = match?.group(1);
      final build = int.tryParse(match?.group(2) ?? '');
      if (version != null && build != null) candidates.add((version, build));
    }
  }
  if (candidates.isEmpty) return null;
  candidates.sort((left, right) {
    final version = compareVersions(left.$1, right.$1);
    return version != 0 ? version : left.$2.compareTo(right.$2);
  });
  return candidates.last;
}

final _versionPattern = RegExp(r'^\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$');
final _artifactVersionPattern = RegExp(
  r'^(?:deltiecord|send)-(\d+(?:\.\d+){1,3})\+(\d+)-',
  caseSensitive: false,
);

int compareVersions(String left, String right) {
  List<int> parts(String value) => value
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part) ?? 0)
      .toList(growable: true);
  final a = parts(left);
  final b = parts(right);
  final length = a.length > b.length ? a.length : b.length;
  while (a.length < length) {
    a.add(0);
  }
  while (b.length < length) {
    b.add(0);
  }
  for (var index = 0; index < length; index++) {
    if (a[index] != b[index]) return a[index].compareTo(b[index]);
  }
  return 0;
}
