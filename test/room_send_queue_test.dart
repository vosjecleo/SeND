import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/room_send_queue.dart';

void main() {
  test(
    'messages queue behind an upload, independently for each room',
    () async {
      final queue = RoomSendQueue(), upload = Completer<void>();
      final events = <String>[];
      final first = queue.run('one', () async {
        events.add('upload');
        await upload.future;
        events.add('uploaded');
      });
      final second = queue.run('one', () async {
        events.add('next');
      });
      await queue.run('two', () async {
        events.add('other room');
      });
      expect(events, ['upload', 'other room']);
      upload.complete();
      await Future.wait([first, second]);
      expect(events, ['upload', 'other room', 'uploaded', 'next']);
    },
  );
  test('failure does not strand queued messages', () async {
    final queue = RoomSendQueue(), calls = <String>[];
    final first = queue.run('one', () async {
      throw StateError('failed upload');
    });
    final failed = expectLater(first, throwsStateError);
    final second = queue.run('one', () async {
      calls.add('next');
    });
    await failed;
    await second;
    expect(calls, ['next']);
  });
  test(
    'logout cancels pending jobs without sending them in a new session',
    () async {
      final queue = RoomSendQueue(), gate = Completer<void>();
      var sent = false;
      final first = queue.run('one', () => gate.future);
      final second = queue.run('one', () async {
        sent = true;
      });
      final cancelled = expectLater(second, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      queue.cancelPending();
      gate.complete();
      await first;
      await cancelled;
      expect(sent, false);
      await queue.run('one', () async {
        sent = true;
      });
      expect(sent, true);
    },
  );
}
