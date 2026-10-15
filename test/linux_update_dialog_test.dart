import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/update_checker.dart';
import 'package:deltiecord/ui/update_dialog.dart';

void main() {
  for (final suffix in [
    '-linux-appimage-x86_64.AppImage',
    '-linux-debian-amd64.deb',
    '-linux-arch-x86_64.pkg.tar.zst',
  ]) {
    testWidgets('offers the correct Linux update flow for $suffix', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = ReleaseCheckResult(
        version: '0.9.39',
        build: 129,
        updateAvailable: true,
        artifacts: [ReleaseArtifact('SeND-0.9.39+129$suffix', 'a' * 64, 1000)],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  showReleaseUpdate(
                    context,
                    result,
                    detectPackage: () async => suffix,
                  );
                },
                child: const Text('Check'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      final appImage = suffix.endsWith('.AppImage');
      expect(
        find.text(appImage ? 'Download update' : 'Download and install'),
        findsOneWidget,
      );
      expect(
        find.textContaining('administrator authentication'),
        appImage ? findsNothing : findsOneWidget,
      );
      expect(find.textContaining('save unsent drafts'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('SeND update available'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
