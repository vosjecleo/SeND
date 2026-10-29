import 'package:deltiecord/ui/threshold_feedback.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('threshold ticks once, re-arms below, $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: active,
            builder: (_, value, _) =>
                ThresholdFeedbackIcon(active: value, icon: Icons.reply),
          ),
        ),
      );
      active.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final transform = tester.widget<Transform>(find.byType(Transform).last);
      expect(transform.transform.entry(0, 0), greaterThan(1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester
            .widget<Transform>(find.byType(Transform).last)
            .transform
            .entry(0, 0),
        closeTo(1, .001),
      );
      await tester.pump(const Duration(seconds: 1));
      final mobile = platform != TargetPlatform.linux;
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate').length,
        mobile ? 1 : 0,
      );
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      expect(
        calls.where((c) => c.method == 'HapticFeedback.vibrate').length,
        mobile ? 2 : 0,
      );
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
