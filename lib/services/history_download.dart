import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'history_scope.dart';
import 'history_decryption_failure.dart';
export 'history_decryption_failure.dart';

enum HistoryDownloadStatus { idle, running, paused, full, complete, error }

class HistoryDownloadRoom {
  const HistoryDownloadRoom(
    this.id,
    this.name, {
    this.kind = HistoryRoomKind.group,
  });
  final String id, name;
  final HistoryRoomKind kind;
}

class HistoryDownloadPage {
  const HistoryDownloadPage({
    required this.rows,
    required this.nextCursor,
    required this.checked,
    this.unavailable = 0,
    this.failures = const [],
  });
  final List<Map<String, Object?>> rows;
  final String? nextCursor;
  final int checked, unavailable;
  final List<HistoryDecryptionFailure> failures;
}

/// Foreground, event-only backfill. Checkpoint only after an admitted page;
/// quota pauses never advance past events that were not indexed.
class HistoryDownload extends ChangeNotifier {
  HistoryDownload({
    required this.fetch,
    required this.append,
    required this.load,
    required this.save,
    required this.canRun,
    this.onRun,
    this.retryEvent,
    this.pageDelay = const Duration(milliseconds: 50),
  });
  final Future<HistoryDownloadPage> Function(String room, String? cursor) fetch;
  final Future<bool> Function(List<Map<String, Object?>> rows) append;
  final Future<Map<String, Object?>?> Function() load;
  final Future<void> Function(Map<String, Object?>? value) save;
  final bool Function() canRun;
  final VoidCallback? onRun;
  final Future<HistoryDownloadPage> Function(
    HistoryDecryptionFailure event,
    bool Function() active,
  )?
  retryEvent;
  final Duration pageDelay;
  HistoryDownloadStatus status = HistoryDownloadStatus.idle;
  String? message;
  List<String> _rooms = [];
  int _position = 0, checked = 0, _untrackedUnavailable = 0, _generation = 0;
  final _failures = <String, HistoryDecryptionFailure>{};
  List<HistoryDecryptionFailure> get failures =>
      List.unmodifiable(_failures.values);
  int get unavailable => _untrackedUnavailable + _failures.length;
  int get untrackedUnavailable => _untrackedUnavailable;
  bool retrying = false;
  String? _cursor;
  final _seen = <String>[];
  bool _closed = false;
  bool _atQuota = false;
  Future<void>? _work;
  int get totalRooms => _rooms.length;
  int get completedRooms => _position;
  String? get currentRoom =>
      _position < _rooms.length ? _rooms[_position] : null;
  bool get running => status == HistoryDownloadStatus.running;
  bool get hasCheckpoint => _rooms.isNotEmpty && _position < _rooms.length;
  Future<void> get done => _work ?? Future.value();
  bool Function() guardForCurrentRun() {
    final generation = _generation;
    return () => _alive(generation) && (running || retrying) && canRun();
  }

  void _changed() {
    if (!_closed) notifyListeners();
  }

  bool _alive(int generation) => !_closed && generation == _generation;

  Future<void> open() async {
    try {
      final data = await load();
      if (_closed || data == null) return;
      final rooms = (data['rooms'] as List).cast<String>();
      final position = (data['position'] as num).toInt();
      final cursor = data['cursor'] as String?;
      final seen = (data['seen'] as List? ?? []).cast<String>();
      if (data['version'] != 1 ||
          rooms.isEmpty ||
          rooms.length > 4096 ||
          rooms.any((r) => !r.startsWith('!') || r.length > 512) ||
          position < 0 ||
          position > rooms.length ||
          (cursor?.length ?? 0) > 4096 ||
          seen.length > 8 ||
          seen.any((s) => s.length > 4096)) {
        throw const FormatException('Invalid checkpoint');
      }
      _rooms = rooms;
      _position = position;
      _cursor = cursor;
      _seen.addAll(seen);
      checked = ((data['checked'] as num?)?.toInt() ?? 0).clamp(
        0,
        9007199254740991,
      );
      final oldUnavailable = ((data['unavailable'] as num?)?.toInt() ?? 0)
          .clamp(0, checked);
      final failed = (data['failures'] as List? ?? const [])
          .map(
            (entry) => HistoryDecryptionFailure.fromMap(
              Map<String, Object?>.from(entry as Map),
            ),
          )
          .toList();
      if (failed.length > 10000 ||
          utf8
                  .encode(jsonEncode(failed.map((e) => e.toMap()).toList()))
                  .length >
              2 * 1048576) {
        throw const FormatException('Failed-event list too large');
      }
      _failures.addEntries(failed.map((event) => MapEntry(event.key, event)));
      _untrackedUnavailable = data['untrackedUnavailable'] is num
          ? (data['untrackedUnavailable'] as num).toInt().clamp(
              0,
              oldUnavailable,
            )
          : (oldUnavailable - _failures.length).clamp(0, oldUnavailable);
      _atQuota = data['atQuota'] == true;
      status = _atQuota && (hasCheckpoint || _failures.isNotEmpty)
          ? HistoryDownloadStatus.full
          : hasCheckpoint
          ? HistoryDownloadStatus.paused
          : HistoryDownloadStatus.complete;
      message = _atQuota
          ? 'Search storage is full. Increase the cache limit or free space, then resume.'
          : hasCheckpoint
          ? 'Saved progress is ready to resume.'
          : null;
    } catch (_) {
      _rooms = [];
      _cursor = null;
      _failures.clear();
      _untrackedUnavailable = 0;
      status = HistoryDownloadStatus.error;
      message =
          'Saved history progress could not be read. Start a new download.';
    }
    _changed();
  }

  Map<String, Object?> _checkpoint() => {
    'version': 1,
    'rooms': _rooms,
    'position': _position,
    'cursor': _cursor,
    'seen': List.of(_seen),
    'checked': checked,
    'unavailable': unavailable,
    'untrackedUnavailable': _untrackedUnavailable,
    'failures': [for (final event in _failures.values) event.toMap()],
    'atQuota': _atQuota,
  };

  Future<bool> _persist() async {
    try {
      await save(_checkpoint());
      return true;
    } catch (_) {
      if (!_closed) {
        status = HistoryDownloadStatus.error;
        message =
            'Could not save download progress. Check available storage and resume.';
        _changed();
      }
      return false;
    }
  }

  Future<void> start(Iterable<String> rooms) async {
    if (_closed) return;
    if (retrying) {
      throw StateError(
        'Pause the decryption retry before starting a new download.',
      );
    }
    final selected = rooms.toSet().toList();
    if (selected.isEmpty ||
        selected.length > 4096 ||
        selected.any((r) => !r.startsWith('!') || r.length > 512)) {
      throw ArgumentError('Choose joined chats to download');
    }
    _generation++;
    _rooms = selected;
    _position = 0;
    _cursor = null;
    _seen.clear();
    checked = 0;
    _untrackedUnavailable = 0;
    _atQuota = false;
    status = HistoryDownloadStatus.paused;
    if (await _persist()) await resume();
  }

  Future<void> resume() async {
    if (_closed || running || retrying || !hasCheckpoint) return;
    if (!canRun()) {
      status = HistoryDownloadStatus.paused;
      message = 'Enable text indexing and keep SeND open to download history.';
      _changed();
      return;
    }
    _atQuota = false;
    if (!await _persist() || _closed) return;
    status = HistoryDownloadStatus.running;
    message = null;
    final generation = ++_generation;
    onRun?.call();
    final previous = _work;
    _work = () async {
      if (previous != null) await previous;
      if (_alive(generation)) await _run(generation);
    }();
    _changed();
  }

  void pause({String? reason}) {
    if (_closed || (!running && !retrying)) return;
    _generation++;
    retrying = false;
    status = HistoryDownloadStatus.paused;
    message = reason ?? 'Paused. The last completed page is saved.';
    _changed();
  }

  Future<void> reset() async {
    _generation++;
    _rooms = [];
    _position = checked = _untrackedUnavailable = 0;
    _failures.clear();
    retrying = false;
    _atQuota = false;
    _cursor = null;
    _seen.clear();
    status = HistoryDownloadStatus.idle;
    message = null;
    await save(null);
    _changed();
  }

  Future<void> _run(int generation) async {
    try {
      while (_alive(generation) && currentRoom != null) {
        if (!canRun()) {
          pause(reason: 'Paused. Enable text indexing and keep SeND open.');
          return;
        }
        final page = await fetch(currentRoom!, _cursor);
        if (!_alive(generation)) return;
        final next = page.nextCursor;
        if ((next?.length ?? 0) > 4096 ||
            page.checked < 0 ||
            page.unavailable < 0 ||
            page.failures.length > page.unavailable ||
            page.unavailable > page.checked) {
          throw StateError('Invalid history page');
        }
        final pendingFailures = {
          ..._failures,
          for (final event in page.failures) event.key: event,
        };
        if (pendingFailures.length > 10000 ||
            utf8
                    .encode(
                      jsonEncode(
                        pendingFailures.values.map((e) => e.toMap()).toList(),
                      ),
                    )
                    .length >
                2 * 1048576) {
          status = HistoryDownloadStatus.paused;
          message =
              'The failed-event list is full. Retry decryption before resuming. This page has not been skipped.';
          _changed();
          return;
        }
        if (next != null &&
            (next == _cursor || _seen.contains(next)) &&
            page.checked > 0) {
          status = HistoryDownloadStatus.error;
          message =
              'The server repeated a history page. Resume later to retry.';
          _changed();
          return;
        }
        if (!await append(page.rows)) {
          if (!_alive(generation)) return;
          status = HistoryDownloadStatus.full;
          _atQuota = true;
          message =
              'Search storage is full. Increase the cache limit or free space, then resume.';
          if (await _persist() && _alive(generation)) _changed();
          return;
        }
        if (!_alive(generation)) return;
        checked += page.checked;
        for (final row in page.rows) {
          _failures.remove('${row['room']}\u0000${row['id']}');
        }
        for (final event in page.failures) {
          _failures[event.key] = event;
        }
        _untrackedUnavailable += (page.unavailable - page.failures.length)
            .clamp(0, page.checked);
        if (next == null || next == _cursor) {
          _position++;
          _cursor = null;
          _seen.clear();
        } else {
          _cursor = next;
          _seen.add(next);
          if (_seen.length > 8) _seen.removeAt(0);
        }
        if (!await _persist() || !_alive(generation)) return;
        _changed();
        await Future<void>.delayed(pageDelay);
      }
      if (_alive(generation)) {
        status = HistoryDownloadStatus.complete;
        message = unavailable == 0
            ? 'Finished downloading accessible message history.'
            : 'Finished. Encrypted events missing from search: $unavailable. Review them and retry decryption.';
        _changed();
      }
    } catch (_) {
      if (_alive(generation)) {
        if (!canRun()) {
          pause(reason: 'Paused. Enable text indexing and keep SeND open.');
          return;
        }
        status = HistoryDownloadStatus.error;
        message =
            'History download stopped. Check your connection, storage and room access, then resume.';
        _changed();
      }
    }
  }

  Future<void> retryFailed() async {
    if (_closed ||
        running ||
        retrying ||
        _failures.isEmpty ||
        retryEvent == null) {
      return;
    }
    if (!canRun()) {
      throw StateError(
        'Enable text indexing and keep SeND open to retry decryption.',
      );
    }
    retrying = true;
    _atQuota = false;
    if (status == HistoryDownloadStatus.full) {
      status = hasCheckpoint
          ? HistoryDownloadStatus.paused
          : HistoryDownloadStatus.complete;
    }
    final generation = ++_generation;
    final previous = _work;
    onRun?.call();
    message = 'Retrying decryption...';
    _work = () async {
      if (previous != null) await previous;
      var recovered = 0, nonMessage = 0;
      try {
        for (final event in List.of(_failures.values)) {
          if (!_alive(generation) || !retrying || !canRun()) break;
          try {
            final page = await retryEvent!(event, guardForCurrentRun());
            if (!_alive(generation) || !retrying || !canRun()) break;
            if (page.unavailable > 0) continue;
            if (page.rows.isNotEmpty && !await append(page.rows)) {
              status = HistoryDownloadStatus.full;
              _atQuota = true;
              message =
                  'Search storage is full. Increase the limit, then retry decryption.';
              await _persist();
              return;
            }
            if (!_alive(generation) || !retrying) break;
            if (page.rows.any((row) => row['deleted'] != true)) {
              recovered++;
            } else {
              nonMessage++;
            }
            _failures.remove(event.key);
            if (!await _persist()) return;
            _changed();
          } catch (_) {
            /* Keep inaccessible events for the next explicit retry. */
          }
          await Future<void>.delayed(pageDelay);
        }
        if (_alive(generation)) {
          message =
              'Recovered and indexed: $recovered. Redacted or non-message: $nonMessage. Still unavailable: $unavailable.';
          await _persist();
        }
      } finally {
        if (_alive(generation)) {
          retrying = false;
          _changed();
        }
      }
    }();
    _changed();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
