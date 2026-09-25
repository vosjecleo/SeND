import 'dart:async';
import 'package:flutter/material.dart';
import '../services/application_visibility.dart';
import '../services/update_checker.dart';
import '../version.dart';
import 'update_dialog.dart';

/// Rechecks long-lived mobile sessions. Compiled constants identify the running
/// PWA, unlike version.json which may already describe newly deployed code.
class StartupUpdateGate extends StatefulWidget {
  const StartupUpdateGate({
    required this.child,
    this.check,
    this.present,
    this.now,
    super.key,
  });
  final Widget child;
  final Future<ReleaseCheckResult> Function()? check;
  final Future<void> Function(BuildContext, ReleaseCheckResult)? present;
  final DateTime Function()? now;
  @override
  State<StartupUpdateGate> createState() => _StartupUpdateGateState();
}

class _StartupUpdateGateState extends State<StartupUpdateGate>
    with WidgetsBindingObserver {
  static final _shown = <String>{};
  bool _checking = false;
  int _failures = 0;
  DateTime? _nextCheck;
  ReleaseCheckResult? _pending;
  Timer? _poll;
  DateTime get _now => widget.now?.call() ?? DateTime.now();
  bool get _visible => applicationIsForeground(
    WidgetsBinding.instance.lifecycleState,
    viewFocused: true,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_check()));
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_check()),
    );
  }

  Future<void> _check() async {
    if (!mounted || _checking || !_visible) return;
    _checking = true;
    try {
      if (_pending == null &&
          (_nextCheck == null || !_now.isBefore(_nextCheck!))) {
        final checker = UpdateChecker();
        try {
          final result =
              await (widget.check?.call() ??
                  checker.check(
                    currentVersion: deltiecordVersion,
                    currentBuild: int.parse(deltiecordBuildNumber),
                    stableOnly: false,
                  ));
          _nextCheck = _now.add(const Duration(minutes: 5));
          _failures = 0;
          if (result.updateAvailable &&
              !_shown.contains('${result.version}+${result.build}')) {
            _pending = result;
          }
        } finally {
          checker.close();
        }
      }
      if (!mounted ||
          !_visible ||
          _pending == null ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      final result = _pending!;
      final key = '${result.version}+${result.build}';
      _pending = null;
      if (!_shown.add(key)) return;
      try {
        await (widget.present ?? showReleaseUpdate)(context, result);
      } catch (_) {
        _shown.remove(key);
        rethrow;
      }
    } catch (_) {
      _failures++;
      _nextCheck = _now.add(Duration(minutes: _failures < 3 ? _failures : 5));
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
