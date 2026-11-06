import 'dart:async';
import 'dart:typed_data';
import 'package:deltiecord/matrix/bounded_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

class _MediaClient extends Fake implements Client {
  _MediaClient(this.httpClient);
  @override
  final http.Client httpClient;
  @override
  Uri get homeserver => Uri.parse('https://matrix.test');
  @override
  String get accessToken => 'synthetic-test-token';
}

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  int get maxFileSize => 16 * 1024 * 1024;
  @override
  Future<Uint8List?> getFile(Uri uri) async => null;
}

class _AttachmentClient extends Client {
  _AttachmentClient(http.Client transport)
    : super(
        'bounded-attachment-test',
        database: _Database(),
        httpClient: transport,
      ) {
    homeserver = Uri.parse('https://matrix.test');
  }
  @override
  bool get encryptionEnabled => true;
  @override
  Future<bool> authenticatedMediaSupported() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final encrypted in [false, true]) {
    test(
      'SDK attachment cannot decrypt or cache an oversized stream, encrypted=$encrypted',
      () async {
        var cancelled = false;
        final client = _AttachmentClient(
          MockClient.streaming(
            (_, _) async => http.StreamedResponse(
              Stream<List<int>>.multi((sink) {
                sink.onCancel = () => cancelled = true;
                sink.add(Uint8List(101));
                sink.close();
              }),
              200,
            ),
          ),
        );
        addTearDown(client.dispose);
        final room = Room(id: '!media:test', client: client);
        final event = Event.fromJson({
          'type': 'm.room.message',
          'event_id': r'$image',
          'sender': '@other:test',
          'origin_server_ts': 1,
          'content': {
            'msgtype': 'm.image',
            'body': 'image',
            'info': {'size': 1, 'mimetype': 'image/png'},
            if (!encrypted) 'url': 'mxc://matrix.test/media',
            if (encrypted)
              'file': {
                'url': 'mxc://matrix.test/media',
                'v': 'v2',
                'iv': 'unused',
                'key': {
                  'k': 'unused',
                  'key_ops': ['decrypt'],
                },
                'hashes': {'sha256': 'unused'},
              },
          },
        }, room);
        await expectLater(
          BoundedMatrixMedia.attachment(event, maximumBytes: 100),
          throwsA(predicate((e) => e.toString().contains('safe size limit'))),
        );
        expect(cancelled, true);
      },
    );
  }
  test('missing or false metadata cannot bypass response-byte limit', () async {
    var cancelled = false;
    var yielded = 0;
    final transport = MockClient.streaming((request, _) async {
      expect(request.followRedirects, false);
      expect(request.headers['authorization'], 'Bearer synthetic-test-token');
      final stream = Stream<List<int>>.multi((sink) {
        sink.onCancel = () => cancelled = true;
        for (var i = 0; i < 10; i++) {
          yielded++;
          sink.add(Uint8List(64));
        }
        sink.close();
      });
      return http.StreamedResponse(stream, 200);
    });
    await expectLater(
      BoundedMatrixMedia.read(
        _MediaClient(transport),
        Uri.parse('https://matrix.test/media'),
        maximumBytes: 100,
      ),
      throwsA(isA<Exception>()),
    );
    expect(cancelled, true);
    expect(yielded, greaterThan(1));
  });
  test(
    'oversized content length and redirects cancel without buffering',
    () async {
      for (final status in [200, 302]) {
        var cancelled = false;
        final transport = MockClient.streaming(
          (_, _) async => http.StreamedResponse(
            Stream<List<int>>.multi((sink) {
              sink.onCancel = () => cancelled = true;
            }),
            status,
            contentLength: 1000,
          ),
        );
        await expectLater(
          BoundedMatrixMedia.read(
            _MediaClient(transport),
            Uri.parse('https://matrix.test/media'),
            maximumBytes: 10,
          ),
          throwsStateError,
        );
        expect(cancelled, true);
      }
    },
  );
  test('authorization never reaches another origin', () async {
    final transport = MockClient(
      (_) async => throw StateError('must not send'),
    );
    await expectLater(
      BoundedMatrixMedia.read(
        _MediaClient(transport),
        Uri.parse('https://other.test/media'),
      ),
      throwsStateError,
    );
  });
  test('inline operations share three slots and release on failure', () async {
    var active = 0, peak = 0;
    final gates = List.generate(9, (_) => Completer<void>());
    final jobs = List.generate(
      9,
      (index) => BoundedMatrixMedia.run(() async {
        active++;
        if (active > peak) peak = active;
        try {
          await gates[index].future;
        } finally {
          active--;
        }
        if (index == 2) throw StateError('synthetic failure');
      }).catchError((Object _) {}),
    );
    await Future<void>.delayed(Duration.zero);
    expect(active, 3);
    for (final gate in gates) {
      gate.complete();
    }
    await Future.wait(jobs);
    expect(peak, 3);
    expect(active, 0);
    expect(await BoundedMatrixMedia.run(() async => 42), 42);
  });
}
