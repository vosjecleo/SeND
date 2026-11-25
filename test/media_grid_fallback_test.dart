import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as image;
import 'package:matrix/matrix.dart';
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/encoded_image_dimensions.dart';
import 'support/backend_browser_fixture_stub.dart'
    if (dart.library.js_interop) 'support/backend_browser_fixture_web.dart';

class _Db extends Fake implements MatrixSdkDatabase {
  final events = <Event>[];
  int historyReads = 0;
  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async {
    historyReads++;
    return events
        .where((e) => e.room.id == room.id)
        .skip(start)
        .take(limit ?? events.length)
        .toList();
  }

  @override
  Future<void> close() async {}
  @override
  int get maxFileSize => 0;
  @override
  Future<Uint8List?> getFile(Uri uri) async => null;
}

class _Client extends Client {
  _Client(http.Client transport, NativeImplementations crypto, {_Db? db})
    : super(
        'grid-test',
        database: db ?? _Db(),
        httpClient: transport,
        nativeImplementations: crypto,
      ) {
    homeserver = Uri.parse('https://test');
  }
  @override
  String get userID => '@me:test';
  @override
  bool get encryptionEnabled => true;
  @override
  Future<bool> authenticatedMediaSupported() async => true;
}

class _Crypto extends Fake implements NativeImplementations {
  _Crypto(this.png);
  final Uint8List png;
  int decryptions = 0;
  @override
  Future<Uint8List?> decryptFile(
    EncryptedFile file, {
    bool retryInDummy = true,
  }) async {
    expect(file.data, [1, 2, 3]);
    expect(file.k, 'synthetic-key');
    decryptions++;
    return png;
  }
}

class _Room extends Room {
  _Room(Client client) : super(id: '!grid:test', client: client) {
    for (final user in ['@me:test', '@friend:test']) {
      setState(
        Event.fromJson({
          'type': 'm.room.member',
          'state_key': user,
          'sender': user,
          'event_id': '\$member-$user',
          'origin_server_ts': 1,
          'content': {'membership': 'join', 'displayname': user},
        }, this),
      );
    }
  }
  late Event photo;
  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => Timeline(
    room: this,
    onUpdate: onUpdate,
    chunk: TimelineChunk(events: [photo], prevBatch: '', nextBatch: ''),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => addTearDown(installBackendBrowserFixture()));
  test(
    'storage recovers an older encrypted-video poster from local history, once per batch',
    () async {
      final db = _Db();
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 80, height: 40)),
      );
      final requests = <Uri>[];
      final client = _Client(
        MockClient((request) async {
          requests.add(request.url);
          expect(request.url.path, endsWith('/test/poster'));
          return http.Response.bytes([1, 2, 3], 200);
        }),
        _Crypto(png),
        db: db,
      );
      final room = _Room(client);
      client.rooms = [room];
      Map<String, Object> file(String id) => {
        'url': 'mxc://test/$id',
        'v': 'v2',
        'key': {
          'kty': 'oct',
          'alg': 'A256CTR',
          'key_ops': ['encrypt', 'decrypt'],
          'ext': true,
          'k': 'synthetic-key',
        },
        'iv': 'synthetic-iv',
        'hashes': {'sha256': 'synthetic-hash'},
      };
      db.events.add(
        Event.fromJson({
          'event_id': r'$saved-video',
          'type': EventTypes.Message,
          'sender': client.userID,
          'origin_server_ts': 1,
          'content': {
            'msgtype': MessageTypes.Video,
            'body': 'video.mp4',
            'file': file('video'),
            'info': {
              'mimetype': 'video/mp4',
              'thumbnail_file': file('poster'),
              'thumbnail_info': {'mimetype': 'image/png', 'size': png.length},
            },
          },
        }, room),
      );
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final files = [
        for (final id in ['video', 'unavailable'])
          {
            'media_id': id,
            'mxc': 'mxc://test/$id',
            'mimetype': 'application/octet-stream',
          },
      ];
      final found = await backend.serverStorageAttachments(
        files,
        isCurrent: () => true,
      );
      expect(found.keys, ['video']);
      expect(found['video']!.id, r'$saved-video');
      expect(db.historyReads, 1);
      expect(requests, isEmpty);
      expect(await backend.loadAttachmentPreview(found['video']!.id), png);
      expect(requests, hasLength(1));
    },
  );
  test(
    'encrypted image without a thumbnail gets a bounded local grid preview before full-screen opening',
    () async {
      final png = Uint8List.fromList(
        image.encodePng(image.Image(width: 640, height: 320)),
      );
      final crypto = _Crypto(png);
      var reads = 0;
      final client = _Client(
        MockClient((request) async {
          reads++;
          return http.Response.bytes([1, 2, 3], 200);
        }),
        crypto,
      );
      final room = _Room(client);
      room.photo = Event.fromJson({
        'event_id': r'$photo',
        'sender': '@friend:test',
        'origin_server_ts': 1,
        'type': 'm.room.message',
        'content': {
          'msgtype': 'm.image',
          'body': 'photo.png',
          'info': {
            'mimetype': 'image/png',
            'size': png.length,
            'w': 640,
            'h': 320,
          },
          'file': {
            'url': 'mxc://test/photo',
            'v': 'v2',
            'key': {
              'kty': 'oct',
              'alg': 'A256CTR',
              'key_ops': ['encrypt', 'decrypt'],
              'ext': true,
              'k': 'synthetic-key',
            },
            'iv': 'synthetic-iv',
            'hashes': {'sha256': 'synthetic-hash'},
          },
        },
      }, room);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      await backend.selectRoom(room.id);
      final preview = await backend.loadAttachmentPreview(r'$photo');
      expect(preview, isNotNull);
      final size = await readEncodedImageDimensions(preview!);
      expect(size!.width, 256);
      expect(size.height, 128);
      expect(reads, 1);
      expect(crypto.decryptions, 1);
      final reference = await backend.serverStorageAttachment({
        'media_id': 'photo',
        'mxc': 'mxc://test/photo',
        'mimetype': 'application/octet-stream',
      });
      expect(reference!.id, r'$photo');
      expect(
        await backend.serverStorageAttachment({
          'media_id': 'unknown',
          'mxc': 'mxc://test/unknown',
          'mimetype': 'application/octet-stream',
        }),
        isNull,
      );
      expect(
        await backend.serverStorageAttachment({
          'media_id': '../bad',
          'mxc': 'mxc://test/../bad',
          'mimetype': 'image/png',
        }),
        isNull,
      );
      expect(await backend.loadAttachmentPreview(r'$photo'), preview);
      expect(reads, 1);
    },
  );
}
