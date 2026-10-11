import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  testWidgets('server rooms show a collapsible member side panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Deltie'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'General',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(
          userId: '@admin:example.org',
          displayName: 'Admin',
          powerLevel: 100,
        ),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    expect(find.text('Members — 2'), findsOneWidget);
    expect(
      find.text('Admin'),
      findsNWidgets(2),
    ); // Display name plus role badge.
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipient-profile-panel')), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-recipient-profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Room tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    final resizeHandle = find.byKey(const Key('side-panel-resize-handle'));
    final resizeTopLeft = tester.getTopLeft(resizeHandle);
    await tester.dragFrom(
      resizeTopLeft + const Offset(2, 100),
      const Offset(-40, 0),
    );
    await tester.pumpAndSettle();
    expect(backend.preferences.sidePanelWidth, greaterThan(310));
    await tester.tap(find.byKey(const Key('side-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    await tester.tap(find.byKey(const Key('side-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('group chats show their members in the right side panel', (
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
          id: '!group:example.org',
          name: 'Friends',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ]
      ..memberList = const [
        RoomMemberSummary(userId: '@deltie:example.org', displayName: 'Deltie'),
        RoomMemberSummary(userId: '@alice:example.org', displayName: 'Alice'),
        RoomMemberSummary(userId: '@bob:example.org', displayName: 'Bob'),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipient-profile-panel')), findsNothing);
    expect(find.byKey(const Key('member-side-panel')), findsOneWidget);
    expect(find.text('Members — 3'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });
}
