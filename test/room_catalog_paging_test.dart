import 'dart:typed_data';
import 'package:image/image.dart' as image;
import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/room_search_panel.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Catalog extends FakeBackend {
  _Catalog() {
    currentRoom = const RoomSummary(
      id: '!r:test',
      name: 'Room',
      lastMessage: '',
      unreadCount: 0,
      usesChannelIcon: true,
    );
    memberList = const [
      RoomMemberSummary(userId: '@Alice:test', displayName: 'Alice'),
    ];
  }
  final loaded = <String, List<ChatMessage>>{}, calls = <String, int>{};
  int downloads = 0;
  List<ChatMessage> all(String kind) => List.generate(
    kind == 'media' ? 25 : 2,
    (i) => ChatMessage(
      id: '$kind-$i',
      sender: 'Alice',
      senderId: '@Alice:test',
      body: kind == 'link' ? 'A link' : 'item',
      formattedBody: kind == 'link'
          ? '<a href="https://example.org/$i">A link</a>'
          : null,
      timestamp: DateTime(2026).subtract(Duration(seconds: i)),
      pending: false,
      attachment: kind == 'link'
          ? null
          : ChatAttachment(
              kind: kind == 'media'
                  ? AttachmentKind.image
                  : AttachmentKind.file,
              name: '$i',
              mimeType: kind == 'media' ? 'image/png' : 'application/pdf',
              size: 100,
              encrypted: true,
              spoiler: false,
            ),
    ),
  );
  @override
  List<ChatMessage> catalogMessagesForRoom(String room, String kind) =>
      loaded[kind] ?? [];
  @override
  bool canLoadMoreCatalog(String room, String kind) =>
      (loaded[kind]?.length ?? 0) < all(kind).length;
  @override
  Future<List<ChatMessage>> loadMoreCatalog(String room, String kind) async {
    calls[kind] = (calls[kind] ?? 0) + 1;
    return loaded[kind] = all(
      kind,
    ).take((loaded[kind]?.length ?? 0) + 10).toList();
  }

  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async {
    downloads++;
    throw StateError('No original preview downloads');
  }
}

class _PreviewCatalog extends _Catalog {
  bool missingThumbnail = false, failPreview = false;
  int previews = 0;
  Uint8List? cached;
  final png = image.encodePng(image.Image(width: 2, height: 2));
  @override
  List<ChatMessage> all(String kind) => [
    ChatMessage(
      id: 'preview',
      pending: false,
      sender: 'Alice',
      body: '',
      timestamp: DateTime(2026),
      attachment: ChatAttachment(
        kind: AttachmentKind.image,
        name: 'photo.png',
        mimeType: 'image/png',
        size: 100,
        encrypted: true,
        spoiler: false,
        hasThumbnail: !missingThumbnail,
      ),
    ),
  ];
  @override
  Future<Uint8List?> loadAttachmentPreview(
    String id, {
    bool Function()? isCurrent,
  }) async {
    previews++;
    if (failPreview) throw StateError('Temporary thumbnail failure');
    return cached ?? (missingThumbnail ? null : png);
  }

  @override
  Uint8List? cachedAttachmentPreview(String id, {bool thumbnail = false}) =>
      thumbnail ? null : cached;
}

void main() {
  Future<void> show(
    WidgetTester tester,
    _Catalog backend,
    RoomSearchSection section,
  ) async {
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
    await tester.pumpAndSettle();
  }

  testWidgets(
    'previews without optional size metadata render without original downloads',
    (tester) async {
      final backend = _PreviewCatalog();
      await show(tester, backend, RoomSearchSection.media);
      expect(find.byType(LifecycleMemoryImage), findsOneWidget);
      expect(backend.downloads, 0);
      expect(backend.previews, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'opening an original repairs a previously empty preview from cache',
    (tester) async {
      final backend = _PreviewCatalog()..missingThumbnail = true;
      await show(tester, backend, RoomSearchSection.media);
      expect(find.byType(LifecycleMemoryImage), findsNothing);
      backend.cached = backend.png;
      backend.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byType(LifecycleMemoryImage), findsOneWidget);
      expect(backend.downloads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed previews have bounded retries and an explicit retry action',
    (tester) async {
      final backend = _PreviewCatalog()..failPreview = true;
      await show(tester, backend, RoomSearchSection.media);
      expect(backend.previews, 1);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(backend.previews, 3);
      await tester.pump(const Duration(seconds: 30));
      expect(backend.previews, 3);
      backend.failPreview = false;
      await tester.tap(find.byTooltip('Retry preview'));
      await tester.pumpAndSettle();
      expect(find.byType(LifecycleMemoryImage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final direct in [false, true]) {
    testWidgets('search hint identifies its ${direct ? 'DM' : 'channel'}', (
      tester,
    ) async {
      final backend = _Catalog()
        ..currentRoom = RoomSummary(
          id: '!r:test',
          name: direct ? '@Alice' : '#General',
          lastMessage: '',
          unreadCount: 0,
          isDirect: direct,
          usesChannelIcon: !direct,
        );
      await show(tester, backend, RoomSearchSection.media);
      expect(
        find.text(direct ? 'Search @Alice' : 'Search #General'),
        findsOneWidget,
      );
    });
  }

  testWidgets(
    'media stays at ten items per explicit page and never fetches originals',
    (tester) async {
      final backend = _Catalog();
      await show(tester, backend, RoomSearchSection.media);
      expect(backend.calls['media'], 1);
      expect(find.text('1–10 · 10 loaded'), findsOneWidget);
      await tester.drag(find.byType(GridView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(backend.calls['media'], 1);
      expect(backend.downloads, 0);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Page 2 of'), findsOneWidget);
      expect(find.byKey(const ValueKey('media-0')), findsNothing);
      await tester.tap(find.textContaining('Page 2 of'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '3');
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.text('21–25 · 25 loaded'), findsOneWidget);
      expect(backend.downloads, 0);
    },
  );
  testWidgets(
    'files and rich links are fetched independently of the active timeline',
    (tester) async {
      final backend = _Catalog();
      await show(tester, backend, RoomSearchSection.files);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(backend.calls['document'], 1);
      await tester.tap(find.text('Links'));
      await tester.pumpAndSettle();
      expect(find.text('A link'), findsNWidgets(2));
      expect(backend.calls['link'], 1);
      await tester.tap(find.text('from:'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsWidgets);
      await tester.tap(find.text('@Alice:test'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        contains('from:@Alice:test'),
      );
    },
  );
}
