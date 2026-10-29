import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:deltiecord/services/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client extends Client {
  _Client() : super('authored-links', database: _Database());
  @override
  String get userID => '@me:test';
}

class _Room extends Room {
  _Room(Client client) : super(id: '!room:test', client: client);
  final sent = <Map<String, dynamic>>[];
  final editedIds = <String?>[];
  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sent.add(content);
    editedIds.add(editEventId);
    return 'event-${sent.length}';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'default compatibility preserves authored Matrix text/HTML, including edits',
    () async {
      final client = _Client();
      final room = _Room(client);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      const text = 'See https://x.com/alice/status/123?s=20';
      const html =
          '<a href="https://twitter.com/alice/status/123?s=20">original link</a>';
      expect(backend.preferences.improveTwitterLinks, true);
      await backend.sendMessage(text, roomId: room.id);
      await backend.sendMessage(
        text,
        roomId: room.id,
        formattedBody: html,
        editMessageId: 'own-event',
      );
      expect(room.sent.map((c) => c['body']), [text, text]);
      expect(room.sent.last['formatted_body'], html);
      expect(room.editedIds.last, 'own-event');
      expect(
        fxTwitterUrl(Uri.parse('https://x.com/alice/status/123'))?.host,
        'fxtwitter.com',
      );
      backend.dispose();
    },
  );
}
