import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/update_checker.dart';
import 'package:deltiecord/ui/startup_update_gate.dart';

void main() {
  testWidgets(
    'mobile checks again on resume, prompts new builds once, not in background',
    (tester) async {
      var clock = DateTime(2026);
      var build = 910;
      var checks = 0;
      final shown = <int>[];
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          home: StartupUpdateGate(
            now: () => clock,
            check: () async {
              checks++;
              return ReleaseCheckResult(
                version: 'test',
                build: build,
                updateAvailable: true,
              );
            },
            present: (_, result) async => shown.add(result.build),
            child: const Scaffold(body: Text('Mobile home')),
          ),
        ),
      );
      await tester.pump();
      expect(shown, [910]);
      clock = clock.add(const Duration(minutes: 6));
      await tester.pump(const Duration(seconds: 30));
      expect(checks, 2);
      expect(shown, [910]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 6));
      build = 911;
      await tester.pump(const Duration(seconds: 30));
      expect(checks, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(shown, [910, 911]);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
