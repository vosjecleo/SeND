import 'package:deltiecord/services/profile_text.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/first_run_tour.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

void main() {
  test('pronouns trim to 16 graphemes without damaging Unicode', () {
    expect(normalizedProfilePronouns(null), isNull);
    expect(normalizedProfilePronouns('  she/her  '), 'she/her');
    expect(normalizedProfilePronouns('👩🏽‍💻' * 20), '👩🏽‍💻' * 16);
    expect(normalizedProfilePronouns('e\u0301' * 20), 'e\u0301' * 16);
  });

  testWidgets('Android onboarding scrolls long pages above fixed buttons', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: Scaffold(body: FirstRunTourDialog(backend: FakeBackend())),
      ),
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scroll = find.byKey(const ValueKey('tour-scroll-2'));
    final close = tester.getRect(find.text('Close'));
    expect(close.bottom, lessThan(640));
    await tester.scrollUntilVisible(
      find.text('Get ntfy from F-Droid'),
      160,
      scrollable: find
          .descendant(of: scroll, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Get ntfy from F-Droid').hitTestable(), findsOneWidget);
    expect(tester.getRect(find.text('Close')), close);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in [280.0, 340.0, 620.0]) {
    testWidgets(
      'profile keeps banner ratio and square avatar at width $width',
      (tester) async {
        const avatarKey = Key('draft-avatar');
        const bannerKey = Key('draft-banner');
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: DeltiecordProfileCard(
                      profile: const UserProfileSummary(
                        userId: '@person:example.org',
                        displayName: 'Person',
                        statusMessage:
                            'A longer status that should not overflow the card',
                        pronouns: '12345678901234567890',
                      ),
                      avatarPreview: const ColoredBox(
                        key: avatarKey,
                        color: Colors.red,
                      ),
                      bannerPreview: const ColoredBox(
                        key: bannerKey,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        final avatar = tester.getSize(find.byKey(avatarKey));
        final banner = tester.getSize(find.byKey(bannerKey));
        expect(avatar.width, avatar.height);
        expect(banner.width / banner.height, closeTo(3, .0001));
        expect(find.textContaining('1234567890123456'), findsOneWidget);
        expect(find.textContaining('12345678901234567'), findsNothing);
      },
    );
  }
}
