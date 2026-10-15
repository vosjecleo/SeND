import 'update_checker.dart';
import 'update_progress.dart';
export 'update_progress.dart';

class PreparedLinuxUpdate {
  bool get isAppImage => false;
  bool get installed => false;
  Future<void> install() async =>
      throw UnsupportedError('Native updates only.');
  Future<void> restart() async =>
      throw UnsupportedError('Native updates only.');
  Future<void> discard() async {}
}

Future<PreparedLinuxUpdate> prepareLinuxUpdate(
  ReleaseArtifact artifact, {
  required String installedSuffix,
  ReleaseArtifact? control,
  void Function(UpdateProgress)? progress,
}) async => throw UnsupportedError('Native updates only.');

Future<String?> installedArtifactSuffix() async => null;
Future<void> installWindowsUpdate(ReleaseArtifact artifact) =>
    Future.error(UnsupportedError('Installer updates require Windows.'));
