import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/profile_card.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short profile statuses shrink without stretching longer ones', (
    tester,
  ) async {
    for (final width in [360.0, 500.0]) {
      Future<Size> bubbleSize(String status) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: DeltiecordProfileCard(
                    preview: true,
                    profile: UserProfileSummary(
                      userId: '@alice:test',
                      displayName: 'Alice',
                      presence: UserPresence.online,
                      statusMessage: status,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final painted = find.descendant(
          of: find.byType(ProfileStatusBubble),
          matching: find.byType(CustomPaint),
        );
        return tester.getSize(painted.first);
      }

      final short = await bubbleSize('Hi');
      final longer = await bubbleSize('Taking a break from writing code');
      expect(short.width, lessThan(60));
      expect(longer.width, greaterThan(short.width));
      final avatarSize = (width * .26).clamp(64.0, 124.0);
      expect(longer.width, lessThanOrEqualTo(width - 28 - avatarSize - 20));
      expect(tester.takeException(), isNull);
    }
  });
}
