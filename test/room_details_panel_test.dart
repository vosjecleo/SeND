import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/room_details_panel.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
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
