import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/archive_navigation.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/mobile/mobile_widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class ArchiveBackend extends FakeBackend {
  @override
  List<RoomSummary> get archivedRooms => const [
    RoomSummary(
      id: 'archived',
      name: 'Archived friend',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: false,
      isDirect: true,
    ),
  ];
}

void main() {
  testWidgets('frame-stepped mobile pull reveals Archive reliably', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivePullList(
            backend: ArchiveBackend(),
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('Room $i')),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final start = tester.getTopLeft(list) + const Offset(250, 90);
    for (var attempt = 0; attempt < 3; attempt++) {
      final gesture = await tester.startGesture(start);
      // Pump between samples, like a physical drag. A batched tester.drag
      // misses scrollable replacement when the hint first appears.
      for (var i = 0; i < 35; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Release to show Archive'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-archive-entry')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('home-archive-entry'))).height,
        36,
      );
      final entry = find.byKey(const ValueKey('home-archive-entry'));
      for (final child in [
        find.byIcon(Icons.archive_outlined),
        find.text('Archive'),
        find.text('1'),
      ]) {
        expect(
          tester.getCenter(find.descendant(of: entry, matching: child)).dy,
          closeTo(tester.getCenter(entry).dy, .01),
        );
      }
      await tester.drag(list, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-archive-entry')), findsNothing);
      tester.widget<ListView>(list).controller!.jumpTo(0);
      await tester.pumpAndSettle();
    }
  });
  for (final mobile in [false, true]) {
    testWidgets(
      'Archive reuses Home navigation and room rows, mobile=$mobile',
      (tester) async {
        final backend = ArchiveBackend()
          ..currentStatus = SessionStatus.signedIn
          ..roomList = const [
            RoomSummary(
              id: 'regular',
              name: 'Regular friend',
              lastMessage: '',
              unreadCount: 0,
              usesChannelIcon: false,
              isDirect: true,
            ),
          ];
        if (mobile) {
          await pumpMobile(tester, backend);
        } else {
          await tester.pumpWidget(DeltiecordApp(backend: backend));
          await tester.pumpAndSettle();
        }
        expect(find.text('Regular friend'), findsOneWidget);
        final homeHeader = tester.getRect(find.text('Home').first);
        backend.setArchiveOpen(true);
        await tester.pumpAndSettle();
        expect(find.text('Archive'), findsOneWidget);
        expect(find.text('Archived friend'), findsOneWidget);
        expect(find.text('Regular friend'), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byTooltip('Settings'), findsWidgets);
        expect(find.byTooltip('Back to Home'), findsNothing);
        expect(tester.getRect(find.text('Archive')), homeHeader);
        final homeEntry = find.byKey(const ValueKey('home-archive-entry'));
        void expectAligned(
          String label,
          String roomId,
          String roomName,
          IconData icon,
        ) {
          final entry = find.byKey(const ValueKey('home-archive-entry'));
          final room = find.byKey(ValueKey(roomId));
          final avatar = find.descendant(
            of: room,
            matching: find.byType(mobile ? MobileRoomAvatar : ThemeAvatar),
          );
          expect(
            tester
                .getCenter(
                  find.descendant(of: entry, matching: find.byIcon(icon)),
                )
                .dx,
            closeTo(tester.getCenter(avatar).dx, .1),
          );
          expect(
            tester
                .getTopLeft(
                  find.descendant(of: entry, matching: find.text(label)),
                )
                .dx,
            closeTo(tester.getTopLeft(find.text(roomName)).dx, .1),
          );
        }

        expectAligned(
          'Home',
          'archived',
          'Archived friend',
          Icons.unarchive_outlined,
        );
        expect(tester.getSize(homeEntry).height, 36);
        expect(
          find.descendant(of: homeEntry, matching: find.text('Home')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: homeEntry,
            matching: find.byIcon(Icons.unarchive_outlined),
          ),
          findsOneWidget,
        );
        expect(
          tester.getBottomLeft(homeEntry).dy,
          lessThanOrEqualTo(tester.getTopLeft(find.text('Archived friend')).dy),
        );
        await tester.tap(homeEntry);
        await tester.pumpAndSettle();
        expect(find.text('Regular friend'), findsOneWidget);
        expect(find.text('Archived friend'), findsNothing);
        if (mobile) {
          final list = find.descendant(
            of: find.byType(ArchivePullList),
            matching: find.byType(ListView),
          );
          final gesture = await tester.startGesture(
            tester.getTopLeft(list) + const Offset(250, 90),
          );
          for (var i = 0; i < 35; i++) {
            await gesture.moveBy(const Offset(0, 10));
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.up();
          await tester.pumpAndSettle();
        }
        expectAligned(
          'Archive',
          'regular',
          'Regular friend',
          Icons.archive_outlined,
        );
      },
    );
  }
  testWidgets('desktop Archive is compact and needs no overscroll', (
    tester,
  ) async {
    final backend = ArchiveBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivePullList(
            alwaysVisible: true,
            backend: backend,
            itemCount: 20,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('Room $i')),
          ),
        ),
      ),
    );
    final entry = find.byKey(const ValueKey('home-archive-entry'));
    expect(entry, findsOneWidget);
    expect(tester.getSize(entry).height, lessThan(56));
    final icon = find.descendant(
      of: entry,
      matching: find.byIcon(Icons.archive_outlined),
    );
    expect(tester.getCenter(icon).dy, closeTo(tester.getCenter(entry).dy, .01));
    for (final label in ['Archive', '1']) {
      expect(
        tester
            .getCenter(find.descendant(of: entry, matching: find.text(label)))
            .dy,
        closeTo(tester.getCenter(entry).dy, .01),
      );
    }
    final position = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: const Offset(0, -180),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Release to show Archive'), findsNothing);
    expect(tester.getTopLeft(entry).dy, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(entry.hitTestable(), findsNothing);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      greaterThan(0),
    );
    tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    expect(backend.archiveOpen, true);
    expect(find.byType(Scrollbar), findsNothing);
  });
  testWidgets('cancelled mobile pull springs back and can be pulled again', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchivePullList(
            backend: ArchiveBackend(),
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 56, child: Text('Room $i')),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, 400));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(list));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    expect(find.text('Keep pulling for Archive'), findsOneWidget);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('Keep pulling for Archive'), findsNothing);
    await tester.drag(list, const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-archive-entry')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
