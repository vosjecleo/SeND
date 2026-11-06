import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/media_gallery.dart';
import 'package:deltiecord/ui/media_album.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

const galleryId = 'synthetic-gallery-0001';
AttachmentDraft draft([String mime = 'image/png']) => AttachmentDraft(
  bytes: Uint8List(8),
  name: 'test',
  mimeType: mime,
  spoiler: false,
);

ChatMessage photo(
  String id,
  int index, {
  String batch = galleryId,
  int count = 3,
  String sender = '@alice:test',
  String? thread,
  bool pending = false,
  bool failed = false,
  bool redacted = false,
}) => ChatMessage(
  id: id,
  sender: sender,
  senderId: sender,
  body: '',
  timestamp: DateTime(2026, 11, 5, 12, index),
  pending: pending,
  failed: failed,
  redacted: redacted,
  threadRootId: thread,
  attachment: ChatAttachment(
    kind: AttachmentKind.image,
    name: 'test.png',
    mimeType: 'image/png',
    encrypted: true,
    spoiler: false,
    size: 8,
    gallery: MediaGalleryMembership(id: batch, index: index, count: count),
  ),
);
ChatMessage text(String id) => ChatMessage(
  id: id,
  sender: 'Bob',
  senderId: '@bob:test',
  body: 'Hello',
  timestamp: DateTime(2026),
  pending: false,
);

class _Queue extends FakeBackend {
  final started = Completer<void>(), release = Completer<void>();
  final sent = <AttachmentDraft>[];
  @override
  Future<List<AttachmentDraft>> prepareAttachmentsForSend(
    List<AttachmentDraft> drafts, {
    void Function(int, String, double?)? onProgress,
  }) async => [
    // Model an encoder returning fresh objects, not copyWith.
    for (final d in drafts)
      AttachmentDraft(
        bytes: d.bytes,
        name: d.name,
        mimeType: d.mimeType,
        spoiler: d.spoiler,
        imagePrepared: true,
      ),
  ];
  @override
  Future<void> sendAttachment(
    AttachmentDraft attachment, {
    String? roomId,
    String? replyToMessageId,
  }) async {
    sent.add(attachment);
    if (sent.length == 1) {
      started.complete();
      await release.future;
    }
  }
}

void main() {
  test('batch metadata is bounded, validated, and survives retry/copy', () {
    final batch = assignMediaGallery([draft(), draft('video/mp4')]);
    expect(batch.map((d) => d.gallery!.index), [0, 1]);
    expect(batch.map((d) => d.gallery!.id).toSet(), hasLength(1));
    expect(
      assignMediaGallery([batch[1]]).single.gallery,
      same(batch[1].gallery),
    );
    expect(
      batch[0].copyWith(caption: 'Changed').gallery,
      same(batch[0].gallery),
    );
    expect(
      assignMediaGallery([draft()]).single.gallery!.id,
      isNot(batch[0].gallery!.id),
    );
    expect(
      assignMediaGallery([
        draft('audio/ogg'),
        draft('application/pdf'),
      ]).every((d) => d.gallery == null),
      true,
    );
    for (final value in [
      null,
      {},
      {'id': galleryId, 'index': -1, 'count': 2},
      {'id': galleryId, 'index': 2, 'count': 2},
      {'id': galleryId, 'index': 0, 'count': 51},
      {'id': 'x', 'index': 0, 'count': 1},
      {'id': galleryId, 'index': '0', 'count': 2},
    ]) {
      expect(MediaGalleryMembership.fromJson(value), isNull);
    }
    expect(
      MediaGalleryMembership.fromJson(batch.first.gallery!.toJson())!.id,
      batch.first.gallery!.id,
    );
  });
  test(
    'interleaved messages and separate submissions do not split or join a gallery',
    () {
      final first = photo('first', 0), last = photo('last', 2);
      final input = [
        photo('single', 0, batch: 'separate-gallery-0002', count: 1),
        last,
        text('comment'),
        photo('middle', 1),
        first,
      ];
      final index = MediaAlbumIndex.fromNewestFirst(
        input,
        roomId: '!room:test',
      );
      expect(index.albums.keys, ['first']);
      expect(index.albums['first']!.map((m) => m.id), [
        'first',
        'middle',
        'last',
      ]);
      expect(index.hiddenMessageIds, {'last', 'middle'});
      expect(index.visibleMessageId('last'), 'first');
      expect(input.map((m) => m.id), [
        'single',
        'last',
        'comment',
        'middle',
        'first',
      ]);
    },
  );
  test('partial and delayed uploads keep the initial card identity', () {
    final first = photo('first', 0, pending: true);
    final a = MediaAlbumIndex.fromNewestFirst([first], roomId: 'room');
    expect(a.albums['first'], [first]);
    final b = MediaAlbumIndex.fromNewestFirst([
      photo('last', 2),
      text('chat'),
      first,
    ], roomId: 'room');
    expect(b.rowIdentity(first), a.rowIdentity(first));
    expect(b.albums['first'], hasLength(2));
  });
  test('sender/thread/room scopes and contradictory positions cannot mix', () {
    final input = [
      photo('a', 0),
      photo('b', 1, sender: '@mallory:test'),
      photo('c', 1, thread: 'thread'),
    ];
    final index = MediaAlbumIndex.fromNewestFirst(input, roomId: 'room');
    expect(index.hiddenMessageIds, isEmpty);
    final duplicate = MediaAlbumIndex.fromNewestFirst([
      photo('a', 0),
      photo('b', 0),
    ]);
    expect(duplicate.albums, isEmpty);
    expect(duplicate.hiddenMessageIds, isEmpty);
    final contradictory = MediaAlbumIndex.fromNewestFirst([
      photo('a', 0),
      photo('b', 1, count: 2),
    ]);
    expect(contradictory.albums, isEmpty);
    expect(
      MediaAlbumIndex.fromNewestFirst([
        input.first,
      ], roomId: 'other').rowIdentity(input.first),
      isNot(index.rowIdentity(input.first)),
    );
  });
  test(
    'gallery row aliases survive older-page loading and release failed members',
    () {
      final keys = GalleryRowKeys(), rows = <String, GlobalKey>{};
      final later = photo('later', 1);
      var index = MediaAlbumIndex.fromNewestFirst([later]);
      keys.bind(index, rows);
      final key = rows['later'];
      final first = photo('first', 0);
      index = MediaAlbumIndex.fromNewestFirst([later, first]);
      keys.bind(index, rows);
      expect(rows['later'], same(key));
      expect(rows['first'], same(key));
      index = MediaAlbumIndex.fromNewestFirst([
        later,
        photo('first', 0, failed: true),
      ]);
      keys.bind(index, rows);
      expect(rows['first'], isNull);
      expect(rows['later'], same(key));
    },
  );
  test(
    'composer assigns before uploading, preserves through preparation and separates next send',
    () async {
      final backend = _Queue();
      addTearDown(backend.dispose);
      final first = backend.submitComposerMessage(
        roomId: 'room',
        text: '',
        attachments: [draft(), draft()],
      );
      await backend.started.future;
      final firstId = backend.sent.first.gallery!.id;
      final second = backend.submitComposerMessage(
        roomId: 'room',
        text: '',
        attachments: [draft()],
      );
      final local = backend.conversationMessages(roomId: 'room', sent: []);
      expect(local, hasLength(3));
      expect(local.map((m) => m.attachment!.gallery!.id).toSet(), hasLength(2));
      backend.release.complete();
      await Future.wait([first, second]);
      expect(backend.sent.take(2).map((d) => d.gallery!.id).toSet(), {firstId});
      expect(backend.sent.last.gallery!.id, isNot(firstId));
    },
  );
}
