import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'widget_test.dart' show FakeBackend;

class PlayingBackend extends FakeBackend {
  UserActivity? activity = UserActivity(
    kind: ActivityKind.game,
    name: 'Counter-Strike: Source',
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
  );
  @override
  UserActivity? activityFor(String userId) => activity;
}

void main() {
  testWidgets(
    'timeline replaces presence with icon and bare name; list wording unchanged',
    (tester) async {
      final backend = PlayingBackend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: Column(
                children: [
                  TimelineActivityStatus(
                    backend: backend,
                    userId: '@peer:test',
                    presence: UserPresence.online,
                    fallback: const Text('Online'),
                  ),
                  ActivityStatus(
                    backend: backend,
                    userId: '@peer:test',
                    presence: UserPresence.online,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Online'), findsNothing);
      expect(find.text('Counter-Strike: Source'), findsOneWidget);
      expect(find.text('Playing Counter-Strike: Source'), findsOneWidget);
      expect(find.byIcon(Icons.sports_esports_outlined), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      backend.activity = null;
      backend.notifyListeners();
      await tester.pump();
      expect(find.text('Online'), findsOneWidget);
    },
  );
  testWidgets('offline timeline never displays cached live activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TimelineActivityStatus(
          backend: PlayingBackend(),
          userId: '@peer:test',
          presence: UserPresence.offline,
          fallback: const Text('Offline'),
        ),
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Counter-Strike: Source'), findsNothing);
  });
}
