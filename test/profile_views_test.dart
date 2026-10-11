import 'dart:async';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('account preview refreshes when profile data arrives', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'Before refresh',
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Before refresh'), findsWidgets);

    backend.testProfile = const UserProfileSummary(
      userId: '@deltie:example.org',
      displayName: 'After refresh',
    );
    backend.testProfileRevision++;
    backend.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Before refresh'), findsNothing);
    expect(find.text('After refresh'), findsWidgets);
  });

  testWidgets('profile editor updates its preview before saving', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'Deltie',
        bio: 'Existing biography',
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Display name'),
      'Preview Name',
    );
    await tester.pump();

    expect(find.text('Preview Name'), findsWidgets);
    expect(find.text('Edit profile — live preview'), findsOneWidget);
    expect(find.text('Profile outline & gradient — top'), findsOneWidget);
    expect(find.text('Profile gradient — bottom'), findsOneWidget);
  });

  testWidgets(
    'Android profile editor separates preview from scrollable fields',
    (tester) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..testProfile = const UserProfileSummary(
          userId: '@deltie:example.org',
          displayName: 'Deltie',
          bio: 'Existing biography',
        );
      await pumpMobile(tester, backend);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Edit profile — live preview'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Display name'), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens an anchored card then full profile from a sender', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!profile:example.org',
          name: 'profiles',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        presence: UserPresence.online,
        bio: 'Matrix enthusiast',
        pronouns: 'she/her',
        timezone: 'Europe/Amsterdam',
        profileColor: 0xffaa2233,
        profileColorSecondary: 0xff2233aa,
      )
      ..messageList = [
        ChatMessage(
          id: r'$profile',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 15),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('profiles'));
    await tester.pump();
    final senderName = find.text('Alice').last;
    final senderTapPosition = tester.getCenter(senderName);
    await tester.tap(senderName);
    await tester.pumpAndSettle();

    expect(find.textContaining('@alice:example.org'), findsOneWidget);
    expect(find.textContaining('she/her'), findsOneWidget);
    expect(find.text('Matrix enthusiast'), findsOneWidget);
    final compactPopup = find.byKey(const Key('compact-profile-popup'));
    expect(compactPopup, findsOneWidget);
    final compactGradient = tester.widget<Container>(
      find.byKey(const Key('profile-card')),
    );
    expect((compactGradient.decoration as BoxDecoration).gradient, isNotNull);
    expect(
      tester.getTopLeft(compactPopup).dx,
      greaterThan(senderTapPosition.dx),
    );
    expect(find.byKey(const Key('profile-side-panel')), findsNothing);
    await tester.tap(find.text('View full profile'));
    await tester.pumpAndSettle();
    // Both the compact and full profile surfaces show cache-first, then
    // independently validate their data in the background.
    expect(backend.profileRefreshRequests, 2);
    expect(find.text('Online'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(
      find.textContaining('Europe/Amsterdam', skipOffstage: false),
      findsNothing,
    );
    final dialog = tester.widget<Dialog>(
      find.byKey(const Key('profile-side-panel')),
    );
    expect(dialog.alignment, Alignment.centerRight);
    expect(dialog.backgroundColor, Colors.transparent);
    final profileCard = tester.widget<Container>(
      find.byKey(const Key('profile-card')),
    );
    expect((profileCard.decoration! as BoxDecoration).gradient, isNotNull);
    await tester.tap(find.byKey(const Key('profile-close-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile-side-panel')), findsNothing);
  });

  testWidgets('profile waits for extension data without generic-state flash', (
    tester,
  ) async {
    final profile = Completer<UserProfileSummary>();
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..profileCompleter = profile
      ..roomList = const [
        RoomSummary(
          id: '!profile:example.org',
          name: 'profiles',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$profile-loading',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello',
          timestamp: DateTime(2026, 8, 16),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('profiles'));
    await tester.pump();
    await tester.tap(find.text('Alice'));
    await tester.pump();

    expect(find.byKey(const Key('profile-loading-state')), findsOneWidget);
    expect(find.text('@alice:example.org'), findsNothing);
    profile.complete(
      const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        bio: 'Loaded profile',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Loaded profile'), findsOneWidget);
  });

  testWidgets('own profile card opens above the lower user panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final userIsland = find.byKey(const Key('current-user-island'));
    await tester.tap(userIsland);
    await tester.pumpAndSettle();

    final popup = find.byKey(const Key('compact-profile-popup'));
    expect(popup, findsOneWidget);
    expect(
      tester.getBottomLeft(popup).dy,
      lessThan(tester.getTopLeft(userIsland).dy),
    );
    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('shows the direct recipient profile beside a wide conversation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
          presence: UserPresence.online,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(
          userId: '@alice:example.org',
          displayName: 'Alice',
          presence: UserPresence.online,
        ),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
        presence: UserPresence.online,
        bio: 'Matrix enthusiast',
        statusMessage: 'Building things',
        timezone: 'Europe/Amsterdam',
        profileColor: 0xffaa2233,
        profileColorSecondary: 0xff2233aa,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    expect(find.text('@alice:example.org'), findsOneWidget);
    expect(find.text('Matrix enthusiast'), findsOneWidget);
    expect(find.text('View full profile'), findsOneWidget);
    expect(find.textContaining('UTC+02'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-presence-online')),
      findsOneWidget,
    );
    final recipientGradient = tester.widget<Container>(
      find.byKey(const Key('profile-card')),
    );
    final recipientDecoration = recipientGradient.decoration as BoxDecoration;
    expect(recipientDecoration.gradient, isNotNull);
    expect(recipientDecoration.border, isNull);
    expect(
      (recipientGradient.foregroundDecoration as BoxDecoration).border,
      isNotNull,
    );
    final panelRect = tester.getRect(
      find.byKey(const Key('recipient-profile-gradient')),
    );
    final aboutRect = tester.getRect(find.text('Matrix enthusiast'));
    final footerRect = tester.getRect(
      find.byKey(const Key('view-full-profile-island')),
    );
    expect(panelRect.bottom, lessThanOrEqualTo(footerRect.top - 8));
    expect(panelRect.top, lessThan(20));
    expect(aboutRect.left - panelRect.left, closeTo(16, .5));
    expect(aboutRect.right, lessThanOrEqualTo(panelRect.right - 16));
    expect(find.text('About me'), findsNothing);
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: find.byKey(const Key('recipient-profile-panel')),
              matching: find.text('Building things'),
            ),
          )
          .dx,
      greaterThan(panelRect.left + 100),
    );
    expect(
      tester.getTopLeft(find.textContaining('UTC+02')).dy,
      greaterThan(aboutRect.bottom),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('view-full-profile-island'))).dy,
      tester.getTopLeft(find.byKey(const Key('message-composer-island'))).dy,
    );

    backend.testProfile = const UserProfileSummary(
      userId: '@alice:example.org',
      displayName: 'Alice',
      presence: UserPresence.away,
      statusMessage: 'Freshly hydrated',
    );
    backend.testProfileRevision++;
    backend.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Freshly hydrated'), findsOneWidget);
  });

  testWidgets('in-chat sender opens a popover without replacing recipient', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct-popover:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
      ]
      ..testProfile = const UserProfileSummary(
        userId: '@alice:example.org',
        displayName: 'Alice',
      )
      ..messageList = [
        ChatMessage(
          id: r'$direct-profile-popover',
          sender: 'Alice',
          senderId: '@alice:example.org',
          body: 'hello from the timeline',
          timestamp: DateTime(2026, 8, 16),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey(r'message-sender-$direct-profile-popover')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('compact-profile-popup')), findsOneWidget);
    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
  });

  testWidgets('Android sender opens a large dismissible profile sheet', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@alice:test',
        displayName: 'Alice Profile',
        bio: 'About Alice',
      )
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$event',
          sender: 'Alice',
          senderId: '@alice:test',
          body: 'hello',
          timestamp: DateTime(2026),
          pending: false,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey(r'swipe-$event')),
        matching: find.text('Alice'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alice Profile'), findsOneWidget);
    expect(find.text('About Alice'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('About Alice'), findsNothing);
  });
}
