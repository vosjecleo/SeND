import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

void main() {
  testWidgets('mobile can create a category in an empty server', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:test'
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')];
    await pumpMobile(tester, backend);
    await tester.tap(find.byKey(const ValueKey('mobile-start-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Category name'),
      'Projects',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(backend.categoryList.single.name, 'Projects');
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('failed category creation keeps the name and allows retry', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:test'
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..failCategoryCreation = true;
    await pumpMobile(tester, backend);
    await tester.tap(find.byKey(const ValueKey('mobile-start-chat')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Category name'),
      'Test',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Could not create the category.'),
      findsOneWidget,
    );
    expect(find.text('Test'), findsOneWidget);
    backend.failCategoryCreation = false;
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(backend.categoryList.single.name, 'Test');
    expect(find.text('Create category'), findsNothing);
  });

  testWidgets('desktop displays categories without any rooms', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:test'
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..categoryList = const [
        ChannelCategorySummary(id: 'empty', name: 'Projects', roomIds: []),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pumpAndSettle();
    expect(find.text('Projects'), findsOneWidget);
  });

  testWidgets('Space categories collapse and expose accessible ordering', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!two:example.org',
          name: 'two',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!one:example.org', '!two:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('WORK'), findsOneWidget);
    await tester.tap(find.text('WORK'));
    await tester.pump();
    expect(backend.categoryCollapseChanges, [('work', true)]);

    await tester.tap(find.text('WORK'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Move up'), findsOneWidget);
    expect(find.text('Move down'), findsOneWidget);
  });

  testWidgets('Space category labels keep casing with trailing chevrons', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!room:example.org',
          name: 'general',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'mixed-category',
          name: 'Mixed Rooms',
          roomIds: ['!room:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final section = find.byKey(const ValueKey('mixed-category'));
    final label = find.descendant(
      of: section,
      matching: find.text('Mixed Rooms'),
    );
    final chevron = find.descendant(
      of: section,
      matching: find.byIcon(Icons.expand_more),
    );
    expect(label, findsOneWidget);
    expect(find.text('MIXED ROOMS'), findsNothing);
    expect(chevron, findsOneWidget);
    expect(
      tester.getTopLeft(chevron).dx,
      greaterThan(tester.getTopRight(label).dx),
    );
    expect(tester.getTopLeft(label).dx, lessThan(120));
    final style = tester.widget<Text>(label).style!;
    expect(style.fontSize, DeltiecordTypeScale.normal - 1);
    expect(style.fontWeight, FontWeight.w700);
    final header = find
        .descendant(of: section, matching: find.byType(GestureDetector))
        .first;
    expect(tester.getSize(header).height, 22);
    final channelTile = find.ancestor(
      of: find.text('general'),
      matching: find.byType(ListTile),
    );
    expect(tester.getSize(channelTile).height, 30);
  });

  testWidgets('channel layout controls follow the configured permission', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..mayArrangeChannels = false
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!one:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const ValueKey('room-drag-grip-!one:example.org')),
      findsNothing,
    );
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await tester.tap(find.text('WORK'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Edit category'), findsNothing);
    expect(find.text('Delete category'), findsNothing);
  });

  testWidgets('channel drag handles are opt-in even for administrators', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..mayArrangeChannels = true
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!one:example.org',
          name: 'one',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(
      find.byKey(const ValueKey('room-drag-grip-!one:example.org')),
      findsNothing,
    );
  });

  testWidgets('rooms can be dragged into a Space category', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:example.org'
      ..currentPreferences = const AppPreferences(
        enableChannelDragAndDrop: true,
      )
      ..spaceList = const [
        SpaceSummary(id: '!space:example.org', name: 'Workspace'),
      ]
      ..roomList = const [
        RoomSummary(
          id: '!loose:example.org',
          name: 'loose',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
        RoomSummary(
          id: '!work:example.org',
          name: 'work room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'work',
          name: 'WORK',
          roomIds: ['!work:example.org'],
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final looseGrip = find.byKey(
      const ValueKey('room-drag-grip-!loose:example.org'),
    );
    await tester.dragFrom(
      tester.getCenter(looseGrip),
      tester.getCenter(find.text('WORK')) - tester.getCenter(looseGrip),
      touchSlopY: 0,
    );
    await tester.pumpAndSettle();

    expect(backend.roomMoves, contains(('!loose:example.org', 'work', null)));
  });

  testWidgets('Android categories keep casing and place chevrons after text', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentSpaceId = '!space:test'
      ..spaceList = const [SpaceSummary(id: '!space:test', name: 'Friends')]
      ..roomList = const [
        RoomSummary(
          id: '!room:test',
          name: 'general',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: true,
        ),
      ]
      ..categoryList = const [
        ChannelCategorySummary(
          id: 'mixed',
          name: 'Mixed Rooms',
          roomIds: ['!room:test'],
        ),
      ];
    await pumpMobile(tester, backend);

    final list = find.byKey(const ValueKey('mobile-space-room-list'));
    final label = find.descendant(of: list, matching: find.text('Mixed Rooms'));
    final chevron = find.descendant(
      of: list,
      matching: find.byIcon(Icons.expand_more),
    );
    expect(label, findsOneWidget);
    expect(find.text('MIXED ROOMS'), findsNothing);
    expect(chevron, findsOneWidget);
    expect(
      tester.getTopLeft(chevron).dx,
      greaterThan(tester.getTopRight(label).dx),
    );
    final style = tester.widget<Text>(label).style!;
    expect(style.fontSize, DeltiecordTypeScale.normal - 1);
    expect(style.fontWeight, FontWeight.w700);
    expect(
      tester
          .getSize(find.ancestor(of: label, matching: find.byType(ListTile)))
          .height,
      24,
    );
    expect(
      tester
          .getSize(
            find.ancestor(
              of: find.text('general'),
              matching: find.byType(ListTile),
            ),
          )
          .height,
      32,
    );
  });
}
