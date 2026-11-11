import 'dart:async';
import 'dart:collection';
import 'package:matrix/matrix.dart';

class _PresenceCheck {
  DateTime? checkedAt, retryAt;
  Object revision = Object();
}

/// Sync delivers immediate updates. Bounded server reads repair missed updates;
/// SDK/database cache entries alone are never evidence of a recent server read.
class PresenceReconciler {
  PresenceReconciler({
    required this.fetch,
    required this.read,
    required this.publish,
    DateTime Function()? now,
    this.interval = const Duration(minutes: 1),
    this.concurrency = 4,
    this.maximumPending = 32,
    this.maximumEntries = 4096,
  }) : assert(concurrency > 0),
       assert(maximumPending >= concurrency),
       assert(maximumEntries >= maximumPending),
       now = now ?? DateTime.now;

  final Future<CachedPresence> Function(String) fetch;
  final CachedPresence? Function(String) read;
  final void Function(String, CachedPresence) publish;
  final DateTime Function() now;
  final Duration interval;
  final int concurrency, maximumPending, maximumEntries;
  final _checks = <String, _PresenceCheck>{};
  final _pending = <String, Completer<CachedPresence?>>{};
  final _queue = Queue<void Function()>();
  int _active = 0, _epoch = 0;
  bool _closed = false;

  _PresenceCheck _check(String id) {
    final value = _checks.remove(id) ?? _PresenceCheck();
    _checks[id] = value;
    while (_checks.length > maximumEntries) {
      final oldest = _checks.keys
          .where((key) => !_pending.containsKey(key))
          .firstOrNull;
      if (oldest == null) break;
      _checks.remove(oldest);
    }
    return value;
  }

  void observeSync(String id) {
    if (_closed) return;
    final check = _check(id);
    check.revision = Object();
    check.checkedAt = now();
    check.retryAt = null;
  }

  void invalidate() {
    _epoch++;
    _checks.clear();
    _queue.clear();
    for (final entry in _pending.entries) {
      entry.value.complete(_closed ? null : read(entry.key));
    }
    _pending.clear();
  }

  Future<CachedPresence?> refresh(String id, {bool force = false}) {
    if (_closed) return Future.value(null);
    if (_pending[id] case final pending?) return pending.future;
    final check = _check(id);
    final time = now();
    if ((!force &&
            check.checkedAt != null &&
            time.difference(check.checkedAt!) < interval) ||
        (check.retryAt?.isAfter(time) ?? false) ||
        _pending.length >= maximumPending) {
      return Future.value(read(id));
    }
    final result = Completer<CachedPresence?>();
    final epoch = _epoch;
    _pending[id] = result;
    _queue.add(() async {
      try {
        if (_closed || epoch != _epoch) {
          result.complete(_closed ? null : read(id));
          return;
        }
        if (!force &&
            check.checkedAt != null &&
            now().difference(check.checkedAt!) < interval) {
          result.complete(read(id));
          return;
        }
        final snapshot = read(id);
        final revision = check.revision;
        try {
          final value = await fetch(id);
          if (!_closed &&
              epoch == _epoch &&
              identical(_checks[id], check) &&
              identical(check.revision, revision) &&
              identical(read(id), snapshot)) {
            check.checkedAt = now();
            check.retryAt = null;
            publish(id, value);
          }
        } catch (error) {
          if (!_closed &&
              epoch == _epoch &&
              identical(check.revision, revision) &&
              identical(read(id), snapshot)) {
            // Explicit loss of visibility must not retain a previously visible
            // status. Network failures and rate limits keep the last known value.
            if (error is MatrixException &&
                error.errcode != 'M_UNRECOGNIZED' &&
                ((error.response?.statusCode == 403 &&
                        error.errcode == 'M_FORBIDDEN') ||
                    error.response?.statusCode == 404)) {
              check.checkedAt = now();
              publish(id, CachedPresence.neverSeen(id));
            } else {
              final retry = error is MatrixException
                  ? error.retryAfterMs ??
                        (error.errcode == 'M_UNRECOGNIZED' ? 600000 : null)
                  : null;
              check.retryAt = now().add(
                Duration(milliseconds: (retry ?? 30000).clamp(1000, 900000)),
              );
            }
          }
        }
        if (!result.isCompleted) result.complete(_closed ? null : read(id));
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      } finally {
        if (identical(_pending[id], result)) _pending.remove(id);
        _active--;
        _pump();
      }
    });
    _pump();
    return result.future;
  }

  void _pump() {
    while (_active < concurrency && _queue.isNotEmpty) {
      _active++;
      _queue.removeFirst()();
    }
  }

  void dispose() {
    _closed = true;
    invalidate();
    // Running reads may finish, but cannot touch this session or issue queued reads.
  }
}
