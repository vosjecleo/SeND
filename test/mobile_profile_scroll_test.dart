import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/mobile/mobile_profile_sheet.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'activity_multidevice_test.dart' show MultiBackend;

class ProfileBackend extends MultiBackend {
  @override
  Future<UserProfileSummary> getUserProfile(
    String id, {
    bool refresh = false,
  }) async => UserProfileSummary(
    userId: id,
    displayName: 'Person',
    bio: List.filled(40, 'Long profile biography').join('\n'),
  );
}

void main() {
  testWidgets(
    'mobile profile keeps frame fixed, inherits activities, scrolls without dismissing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = ProfileBackend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          builder: (_, child) => ActivityScope(backend: backend, child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showMobileProfileSheet(context, backend, '@person:test'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('profile-card'));
      final frame = tester.getRect(card);
      expect(frame.top, lessThan(100));
      expect(frame.bottom, lessThan(844));
      expect(find.text('Currently playing:'), findsOneWidget);
      expect(find.text('Currently listening to:'), findsOneWidget);
      expect(find.text('Completed song'), findsOneWidget);
      final controller = tester
          .widget<DeltiecordProfileCard>(find.byType(DeltiecordProfileCard))
          .scrollController!;
      await tester.drag(card, const Offset(0, -280));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(200));
      expect(tester.getRect(card), frame);
      await tester.drag(card, const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      expect(tester.getRect(card), frame);
      expect(tester.takeException(), isNull);
    },
  );
}
