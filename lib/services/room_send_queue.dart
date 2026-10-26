import 'dart:async';

class QueuedSendCancelled extends StateError {
  QueuedSendCancelled()
    : super('Queued message cancelled because the session ended.');
}

/// Keep each room's sends in order while allowing other rooms to send freely.
/// The caller owns draft recovery; a failed job does not strand later messages.
class RoomSendQueue {
  final _tails = <String, Future<void>>{};
  int _generation = 0;
  int _pending = 0;
  Future<void> run(String roomId, Future<void> Function() send) {
    if (_pending >= 50) {
      return Future.error(
        StateError(
          'Too many queued messages. Wait for the current uploads to finish.',
        ),
      );
    }
    final generation = _generation;
    _pending++;
    final result = (_tails[roomId] ?? Future<void>.value()).then((_) async {
      if (generation != _generation) {
        throw QueuedSendCancelled();
      }
      await send();
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _tails[roomId] = tail;
    unawaited(
      tail.then((_) {
        _pending--;
        if (identical(_tails[roomId], tail)) _tails.remove(roomId);
      }),
    );
    return result;
  }

  void cancelPending() {
    _generation++;
    _tails.clear();
  }
}
