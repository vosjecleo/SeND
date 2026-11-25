import 'dart:async';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/room_search_panel.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _SearchBackend extends FakeBackend {
  int calls = 0;
  Completer<List<ChatMessage>>? delayed;
  @override
  bool get canLoadMoreSearchResults => calls < 5;
  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) async {
    calls++;
    if (delayed != null) return delayed!.future;
    return calls < 5
        ? []
        : [
            ChatMessage(
              id: 'match',
              sender: 'Alice',
              body: 'needle',
              timestamp: DateTime(2026),
              pending: false,
            ),
          ];
  }
}

class _CompleteSearch extends _SearchBackend {
  @override
  bool get canLoadMoreSearchResults => false;
  @override
  Future<List<ChatMessage>> searchRoomHistory(String query) async {
    calls++;
    return List.generate(
      25,
      (i) => ChatMessage(
        id: 'text-$i',
        sender: 'Alice',
        body: 'needle $i',
        timestamp: DateTime(2026).subtract(Duration(seconds: i)),
        pending: false,
      ),
    );
  }
}

class _MediaBackend extends _SearchBackend {
  final rows = <ChatMessage>[];
  bool complete = false;
  bool supplyMore = false;
  @override
  bool canLoadMoreCatalog(String roomId, String kind) => !complete;
  @override
  List<ChatMessage> catalogMessagesForRoom(String roomId, String kind) => rows;
  @override
  Future<List<ChatMessage>> loadMoreCatalog(String roomId, String kind) async {
    calls++;
    if (rows.length == 50) rows.add(media(50, 500));
    if (supplyMore) {
      rows.addAll(List.generate(53, (i) => media(51 + i, -i)));
      complete = true;
    }
    return List.of(rows);
  }

  static ChatMessage media(int index, int seconds) => ChatMessage(
    id: 'photo-$index',
    sender: 'Alice',
    body: '',
    timestamp: DateTime(2026).add(Duration(seconds: seconds)),
    pending: false,
    attachment: const ChatAttachment(
      kind: AttachmentKind.image,
      name: 'Photo',
      mimeType: 'image/png',
      size: 100,
      encrypted: false,
      spoiler: false,
    ),
  );
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _SearchBackend backend, {
    RoomSearchSection section = RoomSearchSection.messages,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
        ),
        home: Scaffold(
          body: RoomSearchPanel(
            backend: backend,
            onOpen: (_) async {},
            initialSection: section,
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Media uses 50 stable rows and waits before opening an incomplete page',
    (tester) async {
      final backend = _MediaBackend()
        ..rows.addAll(
          List.generate(50, (i) => _MediaBackend.media(i, 100 - i)),
        );
      await show(tester, backend, section: RoomSearchSection.media);
      await tester.pumpAndSettle();
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('1–50 · 50 loaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-0')), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(backend.calls, 4);
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-50')), findsNothing);
      backend.supplyMore = true;
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.text('51–100 · 104 loaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-50')), findsOneWidget);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-0')), findsOneWidget);
      expect(backend.calls, 5);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-50')), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('101–104 · 104 loaded'), findsOneWidget);
    },
  );

  testWidgets('query continues past three empty history pages', (tester) async {
    final backend = _SearchBackend();
    await show(tester, backend);
    await tester.enterText(find.byType(TextField), 'needle');
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 350));
    }
    expect(backend.calls, 5);
    expect(find.text('needle'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('text results have explicit ten-item pages and a total', (
    tester,
  ) async {
    final backend = _CompleteSearch();
    await show(tester, backend);
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 3'), findsOneWidget);
    expect(find.text('1–10 · 25 loaded'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(backend.calls, 1);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 3'), findsOneWidget);
    expect(find.text('11–20 · 25 loaded'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 3 of 3'), findsOneWidget);
    expect(find.text('21–25 · 25 loaded'), findsOneWidget);
    expect(backend.calls, 1);
  });
  testWidgets('clearing query rejects late results and clears busy state', (
    tester,
  ) async {
    final backend = _SearchBackend()..delayed = Completer<List<ChatMessage>>();
    await show(tester, backend);
    await tester.enterText(find.byType(TextField), 'needle');
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 350));
    backend.delayed!.complete([
      ChatMessage(
        id: 'late',
        sender: 'Alice',
        body: 'late result',
        timestamp: DateTime(2026),
        pending: false,
      ),
    ]);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('late result'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
