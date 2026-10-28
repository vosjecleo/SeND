import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/history_download.dart';
import 'package:deltiecord/services/history_index.dart';
import 'package:deltiecord/ui/history_download_panel.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  @override
  List<HistoryDownloadRoom> get historyDownloadRooms => const [
    HistoryDownloadRoom('!r:test', 'Alice'),
  ];
}

void main() {
  for (final mobile in [false, true]) {
    testWidgets(
      'history controls confirm, pause at quota and increase/resume, mobile=$mobile',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(mobile ? 430 : 1000, 1000);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final index = HistoryIndex('@me:test')..enabled = true;
        var fits = false, fetched = 0, approvedLimit = 0;
        final job = HistoryDownload(
          fetch: (_, _) async {
            fetched++;
            return const HistoryDownloadPage(
              rows: [
                {'id': 'event'},
              ],
              nextCursor: null,
              checked: 1,
            );
          },
          append: (_) async => fits,
          load: () async => null,
          save: (_) async {},
          canRun: () => index.enabled,
          pageDelay: Duration.zero,
        );
        final backend = _Backend()
          ..currentRoom = const RoomSummary(
            id: '!r:test',
            name: 'Alice',
            lastMessage: '',
            unreadCount: 0,
            usesChannelIcon: false,
          );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              platform: mobile ? TargetPlatform.android : TargetPlatform.linux,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: HistoryDownloadPanel(
                  backend: backend,
                  index: index,
                  download: job,
                  increaseLimit: (limit) async {
                    approvedLimit = limit;
                    index.limitMiB = limit;
                    fits = true;
                    return true;
                  },
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Download history'));
        await tester.pumpAndSettle();
        expect(find.text('Download message history?'), findsOneWidget);
        expect(fetched, 0);
        await tester.tap(find.text('Download history').last);
        await tester.pumpAndSettle();
        expect(job.status, HistoryDownloadStatus.full);
        expect(find.text('Increase limit and resume'), findsOneWidget);
        await tester.tap(find.text('Increase limit and resume'));
        await tester.pumpAndSettle();
        expect(approvedLimit, 0);
        await tester.tap(find.text('Use 250 MiB'));
        await tester.pumpAndSettle();
        expect(approvedLimit, 250);
        expect(job.status, HistoryDownloadStatus.complete);
        expect(fetched, 2);
        await tester.pumpWidget(const SizedBox());
        job.dispose();
        index.dispose();
      },
    );
  }
}
