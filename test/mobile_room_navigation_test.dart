import 'package:deltiecord/app.dart';
import 'package:deltiecord/ui/mobile/mobile_widgets.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('mobile DM hold opens the compact Home menu', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    backend.editableRoomIds.add('!dm:test');
    await pumpMobile(tester, backend);
    await tester.longPress(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Edit DM name'), findsNothing);
    expect(find.text('Copy room link'), findsNothing);
    expect(find.text('Mark as read'), findsOneWidget);
    expect(find.text('Mute room'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('Android Home shows the Space rail and DM-only navigation', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 1,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await pumpMobile(tester, backend);

    expect(find.byKey(const ValueKey('mobile-space-rail')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-user-island')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-navigation-bottom-scrim')),
      findsOneWidget,
    );
    final navigationCard = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('mobile-navigation-card')),
    );
    expect(
      navigationCard.borderRadius,
      const BorderRadius.only(topLeft: DeltiecordCorners.corner),
    );
    final systemBars = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('mobile-system-bars')),
    );
    expect(systemBars.value.statusBarColor, Colors.transparent);
    final background = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('mobile-navigation-background')),
    );
    expect(
      background.color,
      DeltiecordPalette.forMode(DeltiecordThemeMode.regular).rail,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-rail-badge-Home'))),
      const Size.square(54),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-rail-button-Home'))),
      const Size.square(54),
    );
    final edge = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('mobile-rail-separator')),
    );
    expect(edge.foregroundPainter, isNotNull);
  });

  testWidgets('Android rail selection recovers after a long background cycle', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')];
    await pumpMobile(tester, backend);

    await tester.tap(find.byKey(const ValueKey('mobile-rail-button-Friends')));
    await tester.pumpAndSettle();
    expect(backend.selectedSpaceId, '!space:test');
    final refreshesBeforeBackground = backend.applicationRefreshCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(backend.applicationRefreshCount, refreshesBeforeBackground + 1);

    await tester.tap(find.byKey(const ValueKey('mobile-rail-button-Home')));
    await tester.pumpAndSettle();
    expect(backend.selectedSpaceId, isNull);
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile-rail-button-Friends')));
    await tester.pumpAndSettle();
    expect(backend.selectedSpaceId, '!space:test');
    expect(find.text('Friends'), findsWidgets);
  });

  testWidgets('Android DM rows reserve a compact activity age', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = [
        RoomSummary(
          id: '!recent:test',
          name: 'Recent chat',
          lastMessage: 'A preview that must yield before the age overlaps it',
          statusMessage:
              'An online status that must yield before the age overlaps it',
          presence: UserPresence.online,
          lastActivityAt: DateTime.now().subtract(const Duration(hours: 2)),
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await pumpMobile(tester, backend);

    expect(find.text('2h'), findsOneWidget);
    expect(
      find.text('An online status that must yield before the age overlaps it'),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('2h')).dx,
      greaterThan(
        tester
            .getTopLeft(
              find.text(
                'An online status that must yield before the age overlaps it',
              ),
            )
            .dx,
      ),
    );
  });

  testWidgets('Android room opening and navigation slide preserve selection', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!dm:test',
          name: 'Alice',
          lastMessage: 'hello',
          unreadCount: 0,
          usesChannelIcon: false,
          isDirect: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-timeline')), findsOneWidget);
    expect(backend.selectedRoom?.id, '!dm:test');

    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-room-list')), findsOneWidget);
    expect(backend.selectedRoom?.id, '!dm:test');
    final selectedTile = tester.widget<ListTile>(
      find
          .descendant(
            of: find.byKey(const ValueKey('mobile-room-list')),
            matching: find.byType(ListTile),
          )
          .first,
    );
    expect(selectedTile.selected, isTrue);
    final surfaces = tester.widgetList<Material>(
      find.ancestor(
        of: find.descendant(
          of: find.byKey(const ValueKey('mobile-room-list')),
          matching: find.text('Alice'),
        ),
        matching: find.byType(Material),
      ),
    );
    expect(
      surfaces.any(
        (surface) =>
            surface.shape is RoundedRectangleBorder &&
            surface.color != Colors.transparent,
      ),
      isTrue,
    );
  });

  testWidgets('mobile selected server channel has a visible surface', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:test'
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..roomList = const [
        RoomSummary(
          id: '!channel:test',
          name: 'Selected channel',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('Selected channel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-open-navigation')));
    await tester.pumpAndSettle();
    final title = find.descendant(
      of: find.byKey(const ValueKey('mobile-space-room-list')),
      matching: find.text('Selected channel'),
    );
    expect(
      tester
          .widget<ListTile>(
            find.ancestor(of: title, matching: find.byType(ListTile)),
          )
          .selected,
      isTrue,
    );
    final surfaces = tester.widgetList<Material>(
      find.ancestor(of: title, matching: find.byType(Material)),
    );
    expect(
      surfaces.any(
        (surface) =>
            surface.shape is RoundedRectangleBorder &&
            surface.color != Colors.transparent,
      ),
      isTrue,
    );
  });

  testWidgets(
    'mobile DM presence changes and reorder do not compress avatar rows',
    (tester) async {
      RoomSummary room(String id, UserPresence presence) => RoomSummary(
        id: id,
        name: id,
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
        isDirect: true,
        presence: presence,
      );
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedIn
        ..roomList = [
          room('Alice', UserPresence.offline),
          room('Bob', UserPresence.offline),
          room('Carol', UserPresence.offline),
        ];
      await pumpMobile(tester, backend);
      final initial = tester.getSize(find.byKey(const ValueKey('Bob'))).height;
      for (var i = 0; i < 6; i++) {
        backend.roomList = [
          room('Bob', i.isEven ? UserPresence.online : UserPresence.offline),
          room('Carol', UserPresence.offline),
          room('Alice', UserPresence.offline),
        ];
        backend.notifyListeners();
        await tester.pumpAndSettle();
        final bob = find.byKey(const ValueKey('Bob'));
        final carol = find.byKey(const ValueKey('Carol'));
        expect(tester.widget<ListTile>(bob).subtitle, isNull);
        expect(tester.getSize(bob).height, initial);
        expect(
          tester.getBottomLeft(bob).dy,
          lessThanOrEqualTo(tester.getTopLeft(carol).dy),
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('Android header alone opens details and Back dismisses it', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!room:test',
          name: 'General',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await pumpMobile(tester, backend);
    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-open-details')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-details-panel')).hitTestable(),
      findsNothing,
    );
  });

  testWidgets('mobile conversation spacing is stable through reordering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rooms = List.generate(
      4,
      (i) => RoomSummary(
        id: '!r$i:test',
        name: 'Friend $i',
        lastMessage: '',
        unreadCount: 0,
        usesChannelIcon: false,
        isDirect: true,
      ),
    );
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = rooms;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    final height = tester.getSize(find.byKey(ValueKey(rooms.first.id))).height;
    for (var i = 0; i < 6; i++) {
      backend.roomList = backend.roomList.reversed.toList();
      backend.notifyListeners();
      await tester.pumpAndSettle();
      for (final room in rooms) {
        expect(tester.getSize(find.byKey(ValueKey(room.id))).height, height);
      }
    }
  });

  testWidgets('server room identity uses its type icon, not an avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MobileRoomAvatar(
          room: RoomSummary(
            id: '!server-room:test',
            name: 'General',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: true,
          ),
        ),
      ),
    );
    expect(find.byType(MobileAvatar), findsNothing);
    expect(find.byIcon(Icons.tag), findsOneWidget);
  });
}
