import 'package:deltiecord/services/profile_text.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'transparent profile avatars continue the card gradient over the banner',
    (tester) async {
      const boundaryKey = Key('profile-render');
      const avatarKey = Key('transparent-avatar');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: DeltiecordProfileCard(
                    preview: true,
                    minimumHeight: 500,
                    profile: UserProfileSummary(
                      userId: '@person:test',
                      displayName: 'Person',
                      profileColor: 0xffff0000,
                      profileColorSecondary: 0xff00ff00,
                    ),
                    avatarPreview: SizedBox.expand(key: avatarKey),
                    bannerPreview: ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final card = tester.getRect(find.byKey(const Key('profile-card')));
      final avatar = tester.getRect(find.byKey(avatarKey));
      final point = Offset(avatar.center.dx, avatar.top + avatar.height * .2);
      final gradient =
          (tester
                          .widget<Container>(
                            find.byKey(const Key('profile-card')),
                          )
                          .decoration
                      as BoxDecoration)
                  .gradient!
              as LinearGradient;
      final expected = Color.lerp(
        gradient.colors.first,
        gradient.colors.last,
        (point.dy - card.top) / card.height,
      )!;
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final image = await tester.runAsync(() => boundary.toImage());
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final local = point - tester.getTopLeft(find.byKey(boundaryKey));
      final index = (local.dy.floor() * image!.width + local.dx.floor()) * 4;
      final expectedRgb = expected.toARGB32();
      expect(bytes!.getUint8(index), closeTo((expectedRgb >> 16) & 255, 2));
      expect(bytes.getUint8(index + 1), closeTo((expectedRgb >> 8) & 255, 2));
      expect(bytes.getUint8(index + 2), closeTo(expectedRgb & 255, 2));
      image.dispose();
    },
  );
  test('pronouns trim to 16 graphemes without damaging Unicode', () {
    expect(normalizedProfilePronouns(null), isNull);
    expect(normalizedProfilePronouns('  she/her  '), 'she/her');
    expect(normalizedProfilePronouns('👩🏽‍💻' * 20), '👩🏽‍💻' * 16);
    expect(normalizedProfilePronouns('e\u0301' * 20), 'e\u0301' * 16);
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
        expect(banner.width / banner.height, closeTo(2, .0001));
        final avatarRect = tester.getRect(find.byKey(avatarKey));
        final bannerRect = tester.getRect(find.byKey(bannerKey));
        expect(avatarRect.center.dy, closeTo(bannerRect.bottom, .0001));
        expect(find.textContaining('1234567890123456'), findsOneWidget);
        expect(find.textContaining('12345678901234567'), findsNothing);
      },
    );
  }
}
