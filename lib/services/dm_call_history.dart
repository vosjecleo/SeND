/// Durable call notices use normal encrypted Matrix messages. Reconnects are
/// not new calls; server voice channels never enter this recorder.
const callHistoryKey = 'net.send.call';

class DmCallHistory {
  DmCallHistory({
    required this.read,
    required this.load,
    required this.save,
    required this.publish,
    required this.identity,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final Future<List<Map<String, Object?>>> Function(String room) read;
  final Future<Map<String, Object?>?> Function(String room) load;
  final Future<void> Function(String room, Map<String, Object?> record) save;
  final Future<void> Function(
    String room,
    Map<String, Object?> content,
    String transaction,
  )
  publish;
  final String identity;
  final DateTime Function() now;
  final _jobs = <String, Future<void>>{};
  Future<void> _serial(String room, Future<void> Function() action) {
    final job = (_jobs[room] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => action());
    _jobs[room] = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return job;
  }

  Future<Map<String, Object?>?> _active(String room) async {
    final recent = await read(room);
    final ended = recent
        .where((r) => r['phase'] == 'ended')
        .map((r) => r['id'])
        .toSet();
    final cached = await load(room);
    for (final record in recent.where((r) => r['phase'] == 'started')) {
      return ended.contains(record['id']) ? null : record;
    }
    return cached != null &&
            cached['phase'] == 'started' &&
            !ended.contains(cached['id'])
        ? cached
        : null;
  }

  Future<void> joined(String room, {required bool starting}) =>
      _serial(room, () async {
        if (!starting) {
          final record = await _active(room);
          if (record != null) await save(room, record);
          return;
        }
        final time = now().millisecondsSinceEpoch;
        final record = <String, Object?>{
          'id': '$identity:$time',
          'phase': 'started',
          'started_at': time,
        };
        await publish(room, {
          'msgtype': 'm.notice',
          'body': 'Call started',
          callHistoryKey: record,
        }, '${record['id']}:started');
        await save(room, record);
      });
  Future<void> left(
    String room, {
    required bool empty,
    required bool elected,
  }) => _serial(room, () async {
    if (!empty || !elected) return;
    final record = await _active(room);
    if (record == null) return;
    final start = record['started_at'];
    if (start is! int) return;
    final elapsed = (now().millisecondsSinceEpoch - start).clamp(
      0,
      31536000000,
    );
    final total = elapsed ~/ 1000;
    final duration = total >= 3600
        ? '${total ~/ 3600}:${((total % 3600) ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}'
        : '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
    final ended = <String, Object?>{
      ...record,
      'phase': 'ended',
      'duration_ms': elapsed,
    };
    await publish(room, {
      'msgtype': 'm.notice',
      'body': 'Call ended · $duration',
      callHistoryKey: ended,
    }, '${record['id']}:ended');
    await save(room, ended);
  });
}
