import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/ui/navigation_polish.dart';
import 'package:deltiecord/ui/room_details_panel.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

class _MembersBackend extends FakeBackend {
  @override
  UserActivity? activityFor(String userId) => userId == '@online:test'
      ? UserActivity(
          kind: ActivityKind.game,
          name: 'Test Game',
          expiresAt: DateTime.now().add(const Duration(minutes: 1)),
        )
      : null;
}

void main() {
  testWidgets(
    'member groups and compact row heights stay consistent as presence changes',
    (tester) async {
      final backend = _MembersBackend()
        ..currentRoom = const RoomSummary(
          id: '!room:test',
          name: 'Test Room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        )
        ..memberList = const [
          RoomMemberSummary(
            userId: '@offline:test',
            displayName: 'Offline member',
          ),
          RoomMemberSummary(
            userId: '@online:test',
            displayName: 'Online member',
            presence: UserPresence.online,
          ),
          RoomMemberSummary(
            userId: '@mod:test',
            displayName: 'Moderator',
            powerLevel: 100,
            presence: UserPresence.online,
            statusMessage: 'Available',
          ),
        ];
      addTearDown(backend.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: RoomDetailsPanel(
            backend: backend,
            room: backend.currentRoom!,
            onDismiss: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final online = find.byKey(const ValueKey('@online:test'));
      final offline = find.byKey(const ValueKey('@offline:test'));
      final moderator = find.byKey(const ValueKey('@mod:test'));
      expect(find.text('Moderators — 1'), findsOneWidget);
      expect(find.text('Online — 1'), findsOneWidget);
      expect(find.text('Offline — 1'), findsOneWidget);
      expect(
        tester.getTopLeft(moderator).dy,
        lessThan(tester.getTopLeft(online).dy),
      );
      expect(
        tester.getTopLeft(online).dy,
        lessThan(tester.getTopLeft(offline).dy),
      );
      expect(
        find.descendant(of: moderator, matching: find.byType(MemberRoleBadge)),
        findsOneWidget,
      );
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Test Game'), findsOneWidget);
      final height = tester.getSize(online).height;
      expect(height, closeTo(tester.getSize(offline).height, .01));
      expect(height, lessThanOrEqualTo(50));
      backend.memberList = [
        backend.memberList[0],
        const RoomMemberSummary(
          userId: '@online:test',
          displayName: 'Online member',
        ),
        backend.memberList[2],
      ];
      backend.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Offline — 2'), findsOneWidget);
      expect(tester.getSize(online).height, height);
      expect(find.text('Test Game'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('room details keeps tabs, actions and pins in one room view', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentRoom = const RoomSummary(
        id: '!room:test',
        name: 'Lounge',
        lastMessage: '',
        unreadCount: 0,
        topic: 'Say hello',
        usesChannelIcon: true,
      )
      ..memberList = const [
        RoomMemberSummary(
          userId: '@alice:test',
          displayName: 'Alice',
          presence: UserPresence.online,
        ),
      ];
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: RoomDetailsPanel(
          backend: backend,
          room: backend.currentRoom!,
          onDismiss: () => dismissed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lounge'), findsOneWidget);
    expect(find.text('Say hello'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Online — 1'), findsOneWidget);
    for (final label in [
      'Members',
      'Media',
      'Pins',
      'Threads',
      'Links',
      'Files',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byTooltip('Notifications'), findsOneWidget);
    expect(find.byTooltip('Room settings'), findsOneWidget);
    await tester.tap(find.text('Pins'));
    await tester.pumpAndSettle();
    expect(find.text('No pinned messages.'), findsOneWidget);
    expect(dismissed, isFalse);
    await tester.tap(find.text('Threads'));
    await tester.pumpAndSettle();
    expect(find.text('No threads in loaded history.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    expect(dismissed, isTrue);
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });

  testWidgets('direct messages do not expose shared room settings', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentRoom = const RoomSummary(
        id: '!dm:test',
        name: 'Alice',
        lastMessage: '',
        unreadCount: 0,
        isDirect: true,
        usesChannelIcon: false,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: RoomDetailsPanel(
          backend: backend,
          room: backend.currentRoom!,
          onDismiss: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Room settings'), findsNothing);
    expect(find.text('Direct message'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });
}
