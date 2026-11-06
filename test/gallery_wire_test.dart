import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/media_gallery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends Client {
  _Client() : super('gallery-wire-test', database: _Database());
  @override
  String get userID => '@me:test';
  @override
  Future<MediaConfig> getConfig({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async => throw StateError('No config');
}

class _Room extends Room {
  _Room(Client client) : super(id: '!gallery:test', client: client);
  final content = <Map<String, dynamic>>[];
  @override
  Future<String?> sendFileEvent(
    MatrixFile file, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    content.add({
      'msgtype': file.msgType,
      'body': file.name,
      'info': file.info,
      ...?extraContent,
    });
    return '\$sent${content.length}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'gallery metadata reaches the normal SDK media send inside message content',
    () async {
      final client = _Client();
      final room = _Room(client);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final bytes = image.encodePng(image.Image(width: 8, height: 4));
      final batch = assignMediaGallery([
        for (var i = 0; i < 2; i++)
          AttachmentDraft(
            bytes: bytes,
            name: '$i.png',
            mimeType: 'image/png',
            spoiler: i == 1,
            caption: i == 0 ? 'Trip' : null,
            imagePrepared: true,
          ),
      ]);
      for (final draft in batch) {
        await backend.sendAttachment(draft, roomId: room.id);
      }
      expect(room.content, hasLength(2));
      final membership = [
        for (final event in room.content)
          MediaGalleryMembership.fromJson(
            event[MediaGalleryMembership.contentKey],
          )!,
      ];
      expect(membership.map((m) => m.index), [0, 1]);
      expect(membership.map((m) => m.id).toSet(), {batch.first.gallery!.id});
      expect(room.content.first['body'], 'Trip');
      expect(room.content.last['m.spoiler'], true);
      expect(
        room.content.every((e) => e['msgtype'] == MessageTypes.Image),
        true,
      );
    },
  );
}
