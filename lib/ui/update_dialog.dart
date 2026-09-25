import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_checker.dart';
import '../services/update_installation.dart';

Future<void> showReleaseUpdate(
  BuildContext context,
  ReleaseCheckResult result,
) async {
  final suffix = await installedArtifactSuffix();
  if (!context.mounted) return;
  final artifact = result.artifactFor(suffix);
  final canInstall =
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.windows &&
      suffix == '-windows-x64-setup.exe' &&
      artifact != null;
  var busy = false;
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
              if (canInstall)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Download and verify the installer, then review the upgrade in Windows. Finish recordings and uploads first; setup may ask you to close SeND. Your account data is kept.',
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                ),
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
                artifact == null
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
                                  'The installer could not be downloaded, verified or opened. Nothing was installed by SeND. Try the direct download instead.';
                            });
                          }
                        }
                      },
                child: const Text('Download and install'),
              ),
          ],
        ),
      ),
    ),
  );
}
