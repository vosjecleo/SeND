import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';

/// Performs a silent release check with bounded retries after sign-in.
///
/// Update discovery must never delay Matrix startup. Network and parse errors
/// are intentionally ignored here; the explicit checker in Settings remains
/// available for diagnostics and retrying.
class StartupUpdateGate extends StatefulWidget {
  const StartupUpdateGate({required this.child, super.key});

  final Widget child;

  @override
  State<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<StartupUpdateGate>
    with WidgetsBindingObserver {
  static bool _checkedThisProcess = false;
  bool _checking = false;
  int _attempts = 0;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_checkedThisProcess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_check());
      });
    }
  }

  Future<void> _check() async {
    if (!mounted || _checking || _checkedThisProcess || _attempts >= 3) return;
    _checking = true;
    _attempts++;
    final checker = UpdateChecker();
    try {
      final package = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(package.buildNumber) ?? 0;
      final result = await checker.check(
        currentVersion: package.version,
        currentBuild: currentBuild,
        stableOnly: false,
      );
      if (!mounted) return;
      _checkedThisProcess = true;
      if (!mounted || !result.updateAvailable) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Deltiecord update available'),
          content: Text(
            'Version ${result.version} build ${result.build} is available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                launchUrl(
                  Uri.parse(deltiecordReleasesPage),
                  mode: LaunchMode.externalApplication,
                );
              },
              child: const Text('View release'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Startup update checks are advisory and must not affect the session.
      if (mounted && _attempts < 3) {
        _retry?.cancel();
        _retry = Timer(const Duration(minutes: 1), () => unawaited(_check()));
      }
    } finally {
      _checking = false;
      checker.close();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    _retry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
