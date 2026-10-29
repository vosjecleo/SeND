import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/history_index.dart';
import 'package:deltiecord/services/history_index_native.dart';
import 'package:deltiecord/services/history_download.dart';
import 'package:deltiecord/models/chat_models.dart' as models;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('history-test', database: _Database());
  int pages = 0, extraRequests = 0;
  @override
  String get userID => '@me:test';
  @override
  Future<GetRoomEventsResponse> getRoomEvents(
    String roomId,
    Direction dir, {
    String? from,
    String? to,
    int? limit,
    String? filter,
  }) async {
    pages++;
    expect(dir, Direction.b);
    expect(limit, 100);
    return GetRoomEventsResponse(
      start: 'start',
      chunk: [
        MatrixEvent.fromJson({
          'type': 'm.room.message',
          'event_id': '\$text',
          'sender': '@friend:test',
          'origin_server_ts': 1700000000000,
          'content': {'msgtype': 'm.text', 'body': 'hello local history'},
        }),
        MatrixEvent.fromJson({
          'type': 'm.room.message',
          'event_id': '\$image',
          'sender': '@friend:test',
          'origin_server_ts': 1700000001000,
          'content': {
            'msgtype': 'm.image',
            'body': 'photo.png',
            'file': {
              'url': 'mxc://test/private',
              'key': {'k': 'DO_NOT_PERSIST'},
            },
            'info': {'thumbnail_url': 'mxc://test/poster', 'w': 1024, 'h': 512},
          },
        }),
      ],
    );
  }
}

class _Room extends Room {
  _Room(Client client) : super(id: '!r:test', client: client);
  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async => throw StateError('Timeline not loaded in this fixture');
}

class _RedactedClient extends _Client {
  @override
  Future<GetRoomEventsResponse> getRoomEvents(
    String roomId,
    Direction dir, {
    String? from,
    String? to,
    int? limit,
    String? filter,
  }) async => GetRoomEventsResponse(
    start: 'start',
    chunk: [
      MatrixEvent.fromJson({
        'event_id': r'$deleted',
        'type': 'm.room.encrypted',
        'sender': '@friend:test',
        'origin_server_ts': 1700000000000,
        'content': <String, Object?>{},
        'unsigned': {
          'redacted_because': {
            'event_id': r'$redaction',
            'type': 'm.room.redaction',
            'sender': '@friend:test',
            'origin_server_ts': 1700000001000,
            'content': <String, Object?>{},
          },
        },
      }),
      MatrixEvent.fromJson({
        'event_id': r'$missing-key',
        'type': 'm.room.encrypted',
        'sender': '@friend:test',
        'origin_server_ts': 1700000000000,
        'content': {
          'algorithm': 'm.megolm.v1.aes-sha2',
          'session_id': 'missing',
        },
      }),
    ],
  );
}

class _OfflineBackend extends MatrixBackend {
  _OfflineBackend(Client client, HistoryIndex index)
    : super(client: client, historyIndexFactory: (_) => index);
  @override
  models.ConnectionStatus get connectionStatus =>
      models.ConnectionStatus.offline;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'redacted ciphertext deletes stale index content without a false decryption failure',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final client = _RedactedClient();
      client.httpClient = MockClient(
        (_) async => throw StateError('No network'),
      );
      final room = _Room(client);
      client.rooms = [room];
      final index = HistoryIndex(
        '@me:test',
        store: HistoryStore('redaction', database: db),
      );
      final backend = MatrixBackend(
        client: client,
        historyIndexFactory: (_) => index,
      );
      await backend.openHistoryIndex();
      await backend.configureHistoryIndex(true);
      await index.ingest([
        {
          'id': r'$deleted',
          'room': room.id,
          'time': 1,
          'sender': '@friend:test',
          'kind': '',
          'body': 'previously visible',
        },
      ]);
      final job = (await backend.openHistoryDownload())!;
      await job.start([room.id]);
      await job.done;
      expect(await index.readRows([r'$deleted']), isEmpty);
      expect(job.unavailable, 1);
      expect(job.failures.single.eventId, r'$missing-key');
      backend.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.dispose();
    },
  );
  test(
    'offline indexed search pages beyond fifty results without network history',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final client = _Client();
      client.httpClient = MockClient((request) async {
        client.extraRequests++;
        throw StateError('No network');
      });
      final room = _Room(client);
      client.rooms = [room];
      final index = HistoryIndex(
        '@me:test',
        store: HistoryStore('fixture', database: db),
      );
      final backend = _OfflineBackend(client, index);
      await backend.openHistoryIndex();
      await backend.configureHistoryIndex(true);
      await index.ingest(
        List.generate(
          60,
          (i) => <String, Object?>{
            'id': '\$row$i',
            'room': room.id,
            'sender': '@friend:test',
            'time': 1700000000000 + i,
            'kind': '',
            'body': 'needle $i',
          },
        ),
      );
      await backend.selectRoom(room.id);
      final before = client.extraRequests;
      expect((await backend.searchRoomHistory('needle')).length, 50);
      expect(backend.canLoadMoreSearchResults, true);
      expect((await backend.searchRoomHistory('needle')).length, 60);
      expect(backend.canLoadMoreSearchResults, false);
      expect(client.pages, 0);
      expect(client.extraRequests, before);
      backend.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.dispose();
    },
  );
  test(
    'backfill fetches only event pages, stores no media keys, and local search needs no event fetch',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final client = _Client();
      client.httpClient = MockClient((request) async {
        client.extraRequests++;
        throw StateError('No extra HTTP requests allowed');
      });
      final room = _Room(client);
      client.rooms = [room];
      final index = HistoryIndex(
        '@me:test',
        store: HistoryStore('fixture', database: db),
      );
      final backend = MatrixBackend(
        client: client,
        historyIndexFactory: (_) => index,
      );
      await backend.openHistoryIndex();
      await backend.configureHistoryIndex(true);
      final job = (await backend.openHistoryDownload())!;
      await job.start([room.id]);
      await job.done;
      expect(job.status, HistoryDownloadStatus.complete);
      expect(client.pages, 1);
      expect(client.extraRequests, 0);
      final image = await index.readRows(['\$image']);
      expect(image.single['kind'], 'image');
      expect(image.single.values, isNot(contains('DO_NOT_PERSIST')));
      expect(image.single.keys, isNot(contains('file')));
      await backend.selectRoom(room.id);
      final before = client.extraRequests;
      final results = await backend.searchRoomHistory('hello');
      expect(results.single.body, 'hello local history');
      expect(client.pages, 1);
      expect(client.extraRequests, before);
      backend.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await client.dispose();
    },
  );
}
