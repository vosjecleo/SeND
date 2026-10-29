import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/typing_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('shows joined rooms and opens a timeline', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!general:example.org',
          name: 'general',
          lastMessage: 'Hello there',
          unreadCount: 2,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('general'), findsOneWidget);
    await tester.tap(find.text('general'));
    await tester.pump();

    expect(backend.selectedRoom?.id, '!general:example.org');
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('bottom panels align and typing indicator keeps their geometry', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentPreferences = const AppPreferences(fontScale: 1.6)
      ..roomList = const [
        RoomSummary(
          id: '!layout:example.org',
          name: 'layout',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ]
      ..messageList = [
        ChatMessage(
          id: r'$layout',
          sender: 'Alice',
          body: 'Aligned content',
          timestamp: DateTime(2026, 9, 3, 12),
          pending: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('layout'));
    await tester.pumpAndSettle();

    final accountPanel = find.byKey(const Key('current-user-panel'));
    final composerPanel = find.byKey(const Key('message-composer-panel'));
    expect(
      tester.getTopLeft(accountPanel).dy,
      tester.getTopLeft(composerPanel).dy,
    );
    expect(
      tester.getSize(accountPanel).height,
      tester.getSize(composerPanel).height,
    );
    final accountIsland = find.byKey(const Key('current-user-island'));
    final composerIsland = find.byKey(const Key('message-composer-island'));
    expect(
      tester.getTopLeft(accountIsland).dx - tester.getTopLeft(accountPanel).dx,
      10,
    );
    expect(
      tester.getTopLeft(composerIsland).dx -
          tester.getTopLeft(composerPanel).dx,
      5,
    );
    expect(
      tester.getSize(accountIsland).height,
      tester.getSize(composerIsland).height,
    );
    final timelineArea = find.byKey(const Key('conversation-timeline-area'));
    expect(
      tester.getTopRight(accountPanel).dx,
      tester.getTopLeft(timelineArea).dx,
    );
    final messageContent = find.byKey(
      const ValueKey(r'message-content-$layout'),
    );
    expect(
      tester.getTopLeft(messageContent).dx,
      tester.getTopLeft(composerIsland).dx + 55,
    );
    final composerSurface = tester.widget<Container>(composerIsland);
    final composerBorder =
        (composerSurface.decoration! as BoxDecoration).border;
    expect(composerBorder, isNull);
    final composerTop = tester.getTopLeft(composerPanel).dy;

    backend.setTypingNames(const ['Alice']);
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Alice is typing'), findsOneWidget);
    expect(tester.getTopLeft(composerPanel).dy, composerTop);
    expect(
      tester.getSize(find.byKey(const Key('typing-indicator'))).width,
      tester.getSize(find.byKey(const Key('conversation-timeline-area'))).width,
    );
    expect(
      tester.getSize(find.byKey(const Key('typing-indicator'))).height,
      typingIndicatorHeight,
    );
    expect(
      tester.getBottomLeft(find.byKey(const Key('typing-indicator'))).dy,
      composerTop,
    );
    final indicator = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(const Key('typing-indicator')),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(indicator.opacity, 1);
  });

  testWidgets('home DM rows expose presence and stronger visual hierarchy', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!alice:example.org',
          name: 'Alice',
          lastMessage: 'See you tomorrow',
          statusMessage: 'Taking a walk',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
          presence: UserPresence.online,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const Key('presence-!alice:example.org-online')),
      findsOneWidget,
    );
    final name = tester.widget<Text>(find.text('Alice'));
    expect(name.style?.fontSize, DeltiecordTypeScale.bigChat);
    expect(name.style?.fontWeight, FontWeight.w400);
    expect(find.text('See you tomorrow'), findsNothing);
    expect(find.text('Taking a walk'), findsOneWidget);
  });

  testWidgets('room panel filters rooms and starts a new direct message', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!alice:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
        RoomSummary(
          id: '!garden:example.org',
          name: 'Garden club',
          lastMessage: 'plants',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.enterText(
      find.byKey(const Key('desktop-room-search')),
      'garden',
    );
    await tester.pump();
    expect(find.text('Garden club'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);

    await tester.enterText(find.byKey(const Key('desktop-room-search')), '');
    await tester.pump();
    await tester.tap(find.byTooltip('Start chat or create room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start direct message'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-direct-message-id')),
      '@newfriend:example.org',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Message'));
    await tester.pumpAndSettle();

    expect(backend.startedDirectMessageWith, '@newfriend:example.org');
  });

  testWidgets('desktop search remains inline and Escape clears its query', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.enterText(
      find.byKey(const Key('desktop-room-search')),
      'query',
    );
    await tester.pump();
    expect(find.byKey(const Key('desktop-room-search')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const Key('room-search-popup')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('desktop-room-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('bottom user island exposes status, presence, mute, and deafen', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..testProfile = const UserProfileSummary(
        userId: '@deltie:example.org',
        displayName: 'Deltie',
        statusMessage: 'Building strange software',
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Building strange software'), findsOneWidget);
    expect(
      find.byKey(const Key('current-user-presence-online')),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(backend.muted, isTrue);
    final mutedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.mic_off),
        matching: find.byType(IconButton),
      ),
    );
    final errorColor = Theme.of(
      tester.element(find.byIcon(Icons.mic_off)),
    ).colorScheme.error;
    expect(mutedButton.style?.foregroundColor?.resolve({}), errorColor);
    await tester.tap(find.byTooltip('Deafen'));
    await tester.pump();
    expect(backend.deafened, isTrue);
    final deafenedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.headset_off),
        matching: find.byType(IconButton),
      ),
    );
    expect(deafenedButton.style?.foregroundColor?.resolve({}), errorColor);
  });

  testWidgets('room panel width can be resized from its main-screen border', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.drag(
      find.byKey(const Key('room-panel-resize-handle')),
      const Offset(40, 0),
    );
    await tester.pump();

    expect(backend.preferences.roomPanelWidth, greaterThan(280));
  });

  testWidgets('room panel survives transient narrow window constraints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(470, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;

    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('room-panel-resize-handle')), findsOneWidget);
  });

  testWidgets('right clicking a DM exposes the compact Home menu', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..editableRoomIds.add('!direct:example.org')
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!direct:example.org',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await revealMessageActions(tester, find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Edit DM name'), findsNothing);
    expect(find.text('Copy room link'), findsNothing);
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('Mute room'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Leave'));
    await tester.pumpAndSettle();

    expect(backend.leftRoomId, '!direct:example.org');
  });
}
