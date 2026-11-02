import 'dart:async';
import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/encryption.dart';
import 'support/timeline_segment_fixture.dart';

class _Database extends SegmentDatabase {
  @override
  Future<void> transaction(Future<void> Function() action) => action();
}

class _Encryption extends Fake implements Encryption {
  final started = Completer<void>();
  final result = Completer<Event>();
  @override
  bool get enabled => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<Event> decryptRoomEvent(
    Event event, {
    bool store = false,
    EventUpdateType updateType = EventUpdateType.timeline,
  }) {
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

class _Client extends SegmentClient {
  _Client(super.storage, this.crypto);
  final _Encryption crypto;
  @override
  Encryption get encryption => crypto;
}

class _Room extends SegmentRoom {
  _Room(super.client);
  late Event encryptedEvent;
  @override
  Future<Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = Room.defaultHistoryCount,
  }) async {
    final timeline = await super.getTimeline(
      onUpdate: onUpdate,
      eventContextId: eventContextId,
      limit: limit,
    );
    timeline.events.insert(5, encryptedEvent);
    return timeline;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'decryption follows event identity when live insertion shifts its old slot',
    () async {
      final crypto = _Encryption();
      final client = _Client(_Database(), crypto);
      final room = _Room(client);
      client.rooms = [room];
      final backend = MatrixBackend(client: client);
      addTearDown(backend.dispose);
      final encrypted = Event.fromJson({
        ...room.event(5).toJson(),
        'event_id': r'$encrypted',
        'type': EventTypes.Encrypted,
        'content': {
          'algorithm': 'm.megolm.v1.aes-sha2',
          'session_id': 'test-session',
          'ciphertext': 'test',
        },
      }, room);
      room.encryptedEvent = encrypted;
      final opening = backend.selectRoom(room.id);
      await crypto.started.future;
      final incoming = room.event(-1);
      client.onTimelineEvent.add(incoming);
      await settleSegmentStreams();
      crypto.result.complete(
        Event.fromJson({
          ...encrypted.toJson(),
          'type': EventTypes.Message,
          'content': {'msgtype': 'm.text', 'body': 'Decrypted target'},
        }, room),
      );
      await opening;
      final raw = room.timelines.single.events;
      expect(raw.map((e) => e.eventId).toSet().length, raw.length);
      expect(
        raw.singleWhere((e) => e.eventId == r'$event4').body,
        'Synthetic 4',
      );
      expect(
        raw.singleWhere((e) => e.eventId == r'$event-1').body,
        'Synthetic -1',
      );
      expect(
        raw.singleWhere((e) => e.eventId == r'$encrypted').body,
        'Decrypted target',
      );
    },
  );
}
