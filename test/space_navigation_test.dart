import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets('server invitation menu targets the server, mobile=$mobile', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')];
      backend.editableRoomIds.add('!space:test');
      if (mobile) {
        await pumpMobile(tester, backend);
        await tester.longPress(find.byTooltip('Friends'));
      } else {
        await tester.pumpWidget(DeltiecordApp(backend: backend));
        await revealMessageActions(tester, find.byTooltip('Friends'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite to server'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, '@user or @user:homeserver.tld'),
        '@friend:test',
      );
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(backend.sentInvites, [('@friend:test', '!space:test')]);
    });
  }

  testWidgets('selects a Matrix Space from the server bar', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie Club'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.byTooltip('Deltie Club'), findsOneWidget);
    await tester.tap(find.byTooltip('Deltie Club'));
    await tester.pump();

    expect(backend.selectedSpaceId, '!space:example.org');
    expect(find.text('Deltie Club'), findsOneWidget);
  });

  testWidgets('right clicking a Space exposes its management actions', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(
      find.byKey(const ValueKey('space-button-Deltie')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Mute Space'), findsOneWidget);
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.text('Space settings'), findsOneWidget);
    expect(find.text('Leave Space'), findsOneWidget);
    await tester.tap(find.text('Mute Space'));
    await tester.pumpAndSettle();
    expect(backend.mutedRooms, [('!space:example.org', true)]);
  });

  testWidgets('Space settings expose identity, notifications, and layout', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(
          id: '!space:example.org',
          name: 'Deltie',
          topic: 'A test Space',
        ),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!text:example.org',
          name: 'General',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!voice:example.org',
          name: 'Voice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
          presentation: RoomPresentation.voice,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(id: 'general', name: 'General', roomIds: []),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(
      find.byKey(const ValueKey('space-button-Deltie')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Space settings'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('space-settings-avatar-preview')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('space-settings-name')), findsOneWidget);
    expect(find.byKey(const Key('space-settings-topic')), findsOneWidget);
    expect(find.byKey(const Key('space-settings-muted')), findsOneWidget);
    expect(find.text('Manage roles and permissions'), findsOneWidget);
    expect(
      find.text('1 text rooms  •  1 voice rooms  •  1 categories'),
      findsOneWidget,
    );
    expect(find.text('Copy Space link'), findsOneWidget);
  });

  testWidgets('Space profiles reuse the full profile editor with inheritance', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'General name',
        bio: 'General bio',
        statusMessage: 'General status',
      )
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(
      find.byKey(const ValueKey('space-button-Deltie')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Space settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit server profile'));
    await tester.pump();
    await tester.tap(find.text('Edit server profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit server profile — live preview'), findsOneWidget);
    expect(find.text('Use general top colour'), findsOneWidget);
    expect(find.text('Use general avatar'), findsOneWidget);
    expect(find.text('Use general voice tile'), findsOneWidget);
  });

  testWidgets('Space buttons remain square without selected side strips', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Test')];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      tester.getSize(find.byKey(const Key('space-button-Test'))),
      const Size.square(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('space-button-Create Space'))),
      const Size.square(48),
    );
  });
}
