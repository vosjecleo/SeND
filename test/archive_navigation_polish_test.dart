import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/archive_navigation.dart';
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
        backend.setArchiveOpen(true);
        await tester.pumpAndSettle();
        expect(find.text('Archive'), findsOneWidget);
        expect(find.text('Archived friend'), findsOneWidget);
        expect(find.text('Regular friend'), findsNothing);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byTooltip('Settings'), findsWidgets);
        await tester.tap(find.byTooltip('Back to Home'));
        await tester.pumpAndSettle();
        expect(find.text('Regular friend'), findsOneWidget);
        expect(find.text('Archived friend'), findsNothing);
      },
    );
  }
  testWidgets(
    'wheel pulls show guidance and snap to one row only after release',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArchivePullList(
              backend: ArchiveBackend(),
              itemCount: 20,
              itemBuilder: (_, i) =>
                  SizedBox(height: 56, child: Text('Room $i')),
            ),
          ),
        ),
      );
      final position = tester.getCenter(find.byType(ListView));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(find.text('Keep scrolling for Archive'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-archive-entry')), findsNothing);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(0, -120),
        ),
      );
      await tester.pump();
      expect(find.text('Release to show Archive'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('home-archive-entry'))).height,
        56,
      );
      expect(find.byType(Scrollbar), findsNothing);
    },
  );
}
