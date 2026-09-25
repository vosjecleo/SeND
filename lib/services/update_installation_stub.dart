import 'update_checker.dart';

Future<String?> installedArtifactSuffix() async => null;
Future<void> installWindowsUpdate(ReleaseArtifact artifact) =>
    Future.error(UnsupportedError('Installer updates require Windows.'));
