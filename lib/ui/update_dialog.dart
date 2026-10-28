import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_checker.dart';
import '../services/update_installation.dart';
import '../services/browser_reload.dart';

Future<void> showReleaseUpdate(
  BuildContext context,
  ReleaseCheckResult result, {
  Future<String?> Function()? detectPackage,
}) async {
  final suffix = await (detectPackage ?? installedArtifactSuffix)();
  if (!context.mounted) return;
  final artifact = result.artifactFor(suffix);
  final canInstall =
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      suffix == '-windows-x64-setup.exe' &&
      artifact != null;
  final canInstallLinux =
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.linux &&
      artifact != null &&
      const [
        '-linux-appimage-x86_64.AppImage',
        '-linux-debian-amd64.deb',
        '-linux-arch-x86_64.pkg.tar.zst',
      ].contains(suffix);
  var busy = false;
  var installed = false;
  PreparedLinuxUpdate? prepared;
  UpdateProgress? progress;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          scrollable: true,
          title: const Text('SeND update available'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Version ${result.version} build ${result.build} is available.',
              ),
              if (kIsWeb)
                const Text(
                  'Finish recordings and uploads before reloading; unsent drafts may be lost.',
                ),
              if (canInstall)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Finish recordings and uploads before installing. Your account data will be kept.',
                  ),
                ),
              if (canInstallLinux)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    suffix == '-linux-appimage-x86_64.AppImage'
                        ? 'Finish calls, recordings and uploads, and save your drafts before restarting.'
                        : 'Finish calls, recordings and uploads, and save your drafts before restarting. Installation needs administrator approval and may download files outside your SOCKS proxy.',
                  ),
                ),
              if (busy)
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: progress?.fraction),
                      if (progress != null) Text(progress!.message),
                    ],
                  ),
                ),
              if (installed)
                const Text('Update installed. Restart SeND to use it.'),
              if (prepared?.isAppImage == true && !installed)
                const Text('Update verified and ready to install.'),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (kIsWeb) {
                        reloadBrowserApplication();
                        return;
                      }
                      var opened = false;
                      try {
                        opened = await launchUrl(
                          artifact?.url ?? Uri.parse(deltiecordReleasesPage),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        // Keep the dialog usable if no URL handler is installed.
                      }
                      if (!context.mounted) return;
                      if (opened) {
                        Navigator.pop(context);
                      } else {
                        setState(
                          () => error =
                              'Could not open the download. Please visit $deltiecordReleasesPage',
                        );
                      }
                    },
              child: Text(
                kIsWeb
                    ? 'Reload app'
                    : artifact == null
                    ? 'Choose a download'
                    : 'Take me to the download!',
              ),
            ),
            if (canInstall)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await installWindowsUpdate(artifact);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (context.mounted) {
                            setState(() {
                              busy = false;
                              error =
                                  'Could not download, verify or open the installer. SeND has not installed anything. Try the direct download.';
                            });
                          }
                        }
                      },
                child: const Text('Download and install'),
              ),
            if (canInstallLinux)
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          if (prepared != null) {
                            await prepared!.restart();
                            return;
                          }
                          prepared = await prepareLinuxUpdate(
                            artifact,
                            installedSuffix: suffix!,
                            control: result.artifactFor('$suffix.zsync'),
                            progress: (value) {
                              if (context.mounted) {
                                setState(() => progress = value);
                              }
                            },
                          );
                          if (!prepared!.isAppImage) {
                            setState(
                              () => progress = const UpdateProgress(
                                'Waiting for the package manager',
                              ),
                            );
                            await prepared!.install();
                            installed = true;
                          }
                          if (context.mounted) setState(() => busy = false);
                        } catch (exception) {
                          if (prepared?.installed == true) {
                            installed = true;
                          } else {
                            await prepared?.discard();
                            prepared = null;
                          }
                          if (context.mounted) {
                            setState(() {
                              busy = false;
                              error = exception is StateError
                                  ? exception.message.toString()
                                  : 'Could not download, verify or install the update. Try the direct download or your package manager.';
                            });
                          }
                        }
                      },
                child: Text(
                  prepared != null
                      ? 'Restart SeND'
                      : suffix == '-linux-appimage-x86_64.AppImage'
                      ? 'Download update'
                      : 'Download and install',
                ),
              ),
          ],
        ),
      ),
    ),
  );
  await prepared?.discard();
}
