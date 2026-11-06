import 'dart:typed_data';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  AttachmentDraft? localDraft;
  @override
  AttachmentDraft? queuedAttachment(String id) => localDraft;
  final bytes = image.encodePng(image.Image(width: 12, height: 6));
  @override
  List<ChatMessage> get messages =>
      currentRoom?.id == 'other' ? [] : messageList;
  @override
  Future<Uint8List> downloadAttachment(
    String id, {
    bool thumbnail = false,
  }) async => bytes;
}

ChatMessage _photo(
  String id,
  int index, {
  String batch = 'gallery-scroll-0001',
  int count = 3,
}) => ChatMessage(
  id: id,
  sender: 'Album author',
  senderId: '@album:test',
  body: index == 0 && count > 1 ? 'Trip' : '',
  timestamp: DateTime(2026, 11, 5, 12, index),
  pending: false,
  attachment: ChatAttachment(
    kind: AttachmentKind.image,
    name: 'photo.png',
    mimeType: 'image/png',
    size: 80,
    encrypted: true,
    spoiler: false,
    width: 12,
    height: 6,
    caption: index == 0 && count > 1 ? 'Trip' : null,
    gallery: MediaGalleryMembership(id: batch, index: index, count: count),
  ),
);
ChatMessage _text(String id, String body) => ChatMessage(
  id: id,
  body: body,
  sender: 'Other author',
  senderId: '@other:test',
  timestamp: DateTime(2026),
  pending: false,
);

void main() {
  testWidgets(
    'gallery tiles refresh prepared bytes without decoding oversized frames',
    (tester) async {
      final backend = _Backend();
      final first = image.encodePng(image.Image(width: 12, height: 6));
      final prepared = image.encodePng(image.Image(width: 6, height: 12));
      backend.localDraft = AttachmentDraft(
        bytes: first,
        name: 'photo.png',
        mimeType: 'image/png',
        spoiler: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 100,
              child: ListenableBuilder(
                listenable: backend,
                builder: (_, _) => MediaAlbumTile(
                  backend: backend,
                  message: _photo('photo', 0),
                  onOpen: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LifecycleMemoryImage>(find.byType(LifecycleMemoryImage))
            .bytes,
        same(first),
      );
      expect(
        tester
            .widget<LifecycleMemoryImage>(find.byType(LifecycleMemoryImage))
            .decodeWidth,
        840,
      );
      backend.localDraft = backend.localDraft!.copyWith(bytes: prepared);
      backend.notifyListeners();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LifecycleMemoryImage>(find.byType(LifecycleMemoryImage))
            .bytes,
        same(prepared),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    },
  );
  for (final mobile in [false, true]) {
    testWidgets(
      'gallery grows across comments/pages and scrolling/room reuse stays live, mobile=$mobile',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = mobile
            ? const Size(430, 900)
            : const Size(1440, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        const room = RoomSummary(
          id: 'room',
          name: 'Gallery test',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        const other = RoomSummary(
          id: 'other',
          name: 'Other chat',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        );
        final history = [
          for (var i = 0; i < 80; i++) _text('old-$i', 'History $i'),
        ];
        final backend = _Backend()
          ..currentStatus = SessionStatus.signedIn
          ..currentRoom = room
          ..roomList = [room, other]
          ..messageList = [_photo('middle', 1), ...history];
        await tester.pumpWidget(
          DeltiecordApp(
            backend: backend,
            platformOverride: mobile
                ? TargetPlatform.android
                : TargetPlatform.linux,
          ),
        );
        await tester.pumpAndSettle();
        if (mobile) {
          await tester.tap(find.text(room.name).hitTestable().first);
          await tester.pumpAndSettle();
        }
        expect(find.byType(MediaAlbumGrid), findsOneWidget);
        final keyed = find.ancestor(
          // Dismissible owns an internal content key which is deliberately
          // replaced when the reply target changes. Check the timeline row,
          // not that gesture's private subtree.
          of: mobile
              ? find
                    .ancestor(
                      of: find.byType(MediaAlbumGrid),
                      matching: find.byType(Dismissible),
                    )
                    .first
              : find.byType(MediaAlbumGrid),
          matching: find.byWidgetPredicate((w) => w.key is GlobalKey),
        );
        final cardKey = tester.widget(keyed.first).key! as GlobalKey;
        final before = cardKey.currentContext;

        backend.messageList = [
          _photo('last', 2),
          _text('comment', 'Between'),
          _photo('middle', 1),
          _photo('first', 0),
          ...history,
        ];
        backend.notifyListeners();
        await tester.pumpAndSettle();
        expect(cardKey.currentContext, same(before));
        expect(
          tester
              .widget<MediaAlbumGrid>(find.byType(MediaAlbumGrid))
              .messages
              .map((m) => m.id),
          ['first', 'middle', 'last'],
        );
        expect(find.text('Trip'), findsOneWidget);
        expect(
          tester.getRect(find.byType(MediaAlbumGrid)).bottom,
          lessThan(tester.getRect(find.text('Between')).top),
        );

        backend.messageList = [
          _photo('single', 0, count: 1, batch: 'other-gallery-0002'),
          ...backend.messageList,
        ];
        backend.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.byType(MediaAlbumGrid), findsOneWidget);
        expect(
          tester.widget<MediaAlbumGrid>(find.byType(MediaAlbumGrid)).messages,
          hasLength(3),
        );
        final list = find.byKey(
          Key(mobile ? 'mobile-message-timeline' : 'message-timeline'),
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)).first,
        );
        for (var i = 0; i < 4; i++) {
          await tester.drag(list, const Offset(0, 450));
          await tester.pumpAndSettle();
          expect(scroll.position.pixels, greaterThan(0));
          await tester.drag(list, const Offset(0, -450));
          await tester.pumpAndSettle();
        }
        await backend.selectRoom(other.id);
        await tester.pumpAndSettle();
        await backend.selectRoom(room.id);
        await tester.pumpAndSettle();
        final reopened = find.byKey(
          Key(mobile ? 'mobile-message-timeline' : 'message-timeline'),
        );
        await tester.drag(reopened, const Offset(0, 450));
        await tester.pumpAndSettle();
        expect(
          tester
              .state<ScrollableState>(
                find
                    .descendant(of: reopened, matching: find.byType(Scrollable))
                    .first,
              )
              .position
              .pixels,
          greaterThan(0),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        backend.dispose();
      },
    );
  }
}
