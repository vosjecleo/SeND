import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/chat_activity_stamp.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/services/personal_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _PinnedBackend extends FakeBackend {
  _PinnedBackend(this.data);
  final PersonalData data;
  @override
  PersonalData get personalData => data;
}

const _room = RoomSummary(
  id: 'dm',
  name: 'Friend',
  lastMessage: '',
  unreadCount: 0,
  isDirect: true,
  usesChannelIcon: false,
);

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'pinned chat has a trailing pin in the room list, mobile=$mobile',
      (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final data = PersonalData(account: '@me:test', write: (_, _) async {});
        await data.open({});
        try {
          await data.set('pin:dm', true);
          final backend = _PinnedBackend(data)
            ..currentStatus = SessionStatus.signedIn
            ..roomList = const [_room];
          if (mobile) {
            await pumpMobile(tester, backend);
          } else {
            await tester.pumpWidget(DeltiecordApp(backend: backend));
          }
          await tester.pumpAndSettle();
          expect(find.byTooltip('Pinned chat'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await data.close();
        }
      },
    );
  }
  Future<FakeBackend> show(
    WidgetTester tester,
    double width, {
    double height = 700,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [_room]
      ..currentRoom = _room
      ..spaceList = const [SpaceSummary(id: 'space', name: 'Test space')];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pumpAndSettle();
    return backend;
  }

  testWidgets(
    'compact desktop opens spaces from Home and closes on selection',
    (tester) async {
      final backend = await show(tester, 700);
      expect(find.byTooltip('Test space'), findsNothing);
      await tester.tap(find.byTooltip('Show spaces'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Test space'));
      await tester.pumpAndSettle();
      expect(backend.selectedSpaceId, 'space');
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow desktop opens chats beside recipient and dismisses on selection',
    (tester) async {
      await show(tester, 500);
      expect(find.text('Friend'), findsOneWidget);
      await tester.tap(find.byTooltip('Show chats'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.text('Friend').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsNothing,
      );
      expect(find.text('Friend'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drawers dismiss on backdrop, Escape and a return to wide layout',
    (tester) async {
      await show(tester, 700);
      await tester.tap(find.byTooltip('Show spaces'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(650, 100));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Show spaces'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsNothing,
      );
      await tester.tap(find.byTooltip('Show spaces'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(700, 700);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-navigation-scrim')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing preserves the draft and minimum size has a clear guard',
    (tester) async {
      await show(tester, 900);
      await tester.enterText(find.byType(EditableText).last, 'Unsent draft');
      for (final size in [
        const Size(700, 700),
        const Size(500, 700),
        const Size(400, 700),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(find.text('Unsent draft'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      tester.view.physicalSize = const Size(350, 700);
      await tester.pumpAndSettle();
      expect(find.text('Too small! >.<'), findsOneWidget);
      tester.view.physicalSize = const Size(900, 250);
      await tester.pumpAndSettle();
      expect(find.text('Too small! >.<'), findsOneWidget);
      tester.view.physicalSize = const Size(900, 700);
      await tester.pumpAndSettle();
      expect(find.text('Unsent draft'), findsOneWidget);
    },
  );

  testWidgets('chat stamp keeps the pin before the time in the same colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: const Scaffold(body: ChatActivityStamp(age: '2m', pinned: true)),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.push_pin));
    final time = tester.widget<Text>(find.text('2m'));
    expect(icon.color, time.style!.color);
    expect(
      tester.getRect(find.byIcon(Icons.push_pin)).right,
      lessThan(tester.getRect(find.text('2m')).left),
    );
  });
}
