import 'package:deltiecord/services/attachment_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Room room;
  late Client client;
  setUpAll(() async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    final sdkDatabase = await MatrixSdkDatabase.init(
      'attachment-text-test',
      database: database,
      sqfliteFactory: databaseFactoryFfi,
    );
    client = Client('attachment-text-test', database: sdkDatabase);
    room = Room(id: '!room:example.org', client: client);
  });
  tearDownAll(() => client.dispose());
  Event event(Map<String, dynamic> content) => Event.fromJson({
    'event_id': r'$image',
    'sender': '@alice:example.org',
    'origin_server_ts': 1,
    'type': 'm.room.message',
    'content': content,
  }, room);
  for (final type in ['m.image', 'm.video', 'm.audio', 'm.file']) {
    test('$type filename is never manufactured into a caption', () {
      for (final filename in [null, '', 'upload.jpg']) {
        final parsed = attachmentText(
          event({'msgtype': type, 'body': 'upload.jpg', 'filename': ?filename}),
        );
        expect(parsed.name, 'upload.jpg');
        expect(parsed.caption, isNull);
      }
    });
    test('$type reply fallback does not become a filename caption', () {
      final parsed = attachmentText(
        event({
          'msgtype': type,
          'filename': 'upload.jpg',
          'body':
              '> <@bob:example.org> quoted message\n> another line\n\nupload.jpg',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': r'$original'},
          },
        }),
      );
      expect(parsed.name, 'upload.jpg');
      expect(parsed.caption, isNull);
    });
  }
  test('real captions and newlines survive reply fallback removal', () {
    final parsed = attachmentText(
      event({
        'msgtype': 'm.image',
        'filename': 'upload.jpg',
        'body': '> <@bob:example.org> quote\n\nA genuine caption\nsecond line',
      }),
    );
    expect(parsed.caption, 'A genuine caption\nsecond line');
  });
  test('missing body never creates an SDK error caption', () {
    expect(
      attachmentText(
        event({'msgtype': 'm.file', 'filename': 'report.pdf'}),
      ).caption,
      isNull,
    );
  });
}
