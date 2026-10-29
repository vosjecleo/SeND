import 'dart:async';
import 'history_download.dart';

/// Device-local continuity, not a second full-history downloader. All mutations
/// are serialized; cursor writes follow both index admission and failure records.
class HistoryGapRecovery {
  HistoryGapRecovery({
    required this.load,
    required this.save,
    required this.append,
    required this.recordPage,
    required this.fetch,
    required this.canRun,
    this.onFull,
  });
  final Future<Map<String, Object?>?> Function() load;
  final Future<void> Function(Map<String, Object?>?) save;
  final Future<bool> Function(List<Map<String, Object?>>) append;
  final Future<bool> Function(HistoryDownloadPage) recordPage;
  final Future<HistoryDownloadPage> Function(
    String,
    String?,
    String,
    bool Function(),
  )
  fetch;
  final bool Function() canRun;
  final void Function()? onFull;
  final _tips = <String, String>{};
  final _gaps = <Map<String, Object?>>[];
  Future<void> _queue = Future.value();
  bool _closed = false, full = false;
  int _generation = 0;
  int get pending => _gaps.length;
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _active() => !_closed && canRun();
  Map<String, Object?> _state() => {
    'version': 1,
    'tips': Map.of(_tips),
    'gaps': [for (final gap in _gaps) Map.of(gap)],
  };
  Future<void> open() => _serial(() async {
    final state = await load();
    if (state == null) return;
    final tips = Map<String, String>.from(state['tips'] as Map);
    final gaps = (state['gaps'] as List)
        .map((g) => Map<String, Object?>.from(g as Map))
        .toList();
    if (state['version'] != 1 ||
        tips.length > 4096 ||
        gaps.length > 4096 ||
        tips.entries.any((e) => !_room(e.key) || !_event(e.value)) ||
        gaps.any(
          (g) =>
              !_room(g['room']) ||
              !_event(g['anchor']) ||
              (g['cursor'] != null &&
                  (g['cursor'] is! String ||
                      (g['cursor'] as String).length > 4096)) ||
              (g['seen'] != null &&
                  (g['seen'] is! List ||
                      (g['seen'] as List).length > 8 ||
                      (g['seen'] as List).any(
                        (s) => s is! String || s.length > 4096,
                      ))),
        )) {
      throw const FormatException('Invalid search continuity state');
    }
    _tips.addAll(tips);
    _gaps.addAll(gaps);
  });
  static bool _room(Object? id) =>
      id is String && id.startsWith('!') && id.length <= 512;
  static bool _event(Object? id) =>
      id is String && id.startsWith(r'$') && id.length <= 512;

  Future<void> defer(String room, List<String> ids) => _serial(() async {
    if (_closed) return;
    final old = _tips[room];
    if (old == null ||
        ids.contains(old) ||
        _gaps.any((g) => g['room'] == room && g['anchor'] == old)) {
      return;
    }
    if (_gaps.length >= 4096) throw StateError('Too many pending search gaps');
    _gaps.add({'room': room, 'anchor': old, 'cursor': null});
    await save(_state());
  });

  /// Sync IDs are chronological. A first observation establishes a baseline,
  /// never an implicit request for the room's entire lifetime history.
  Future<void> observe(
    String room,
    HistoryDownloadPage page, {
    required bool limited,
    String? previousBatch,
    bool Function()? allowed,
  }) => _serial(() async {
    if (_closed ||
        allowed?.call() == false ||
        !_room(room) ||
        page.eventIds.isEmpty) {
      return;
    }
    final latest = page.eventIds.last;
    if (!_event(latest)) return;
    final old = _tips[room];
    Map<String, Object?>? gap;
    Future<Map<String, Object?>?> ensureGap() async {
      if (old == null || page.eventIds.contains(old)) return null;
      final existing = _gaps
          .where((g) => g['room'] == room && g['anchor'] == old)
          .firstOrNull;
      if (existing != null) return existing;
      if (_gaps.length >= 4096) {
        throw StateError('Too many pending search gaps');
      }
      // Persist the obligation before admitting or advancing the new tip.
      // Starting at the current head also covers an interrupted sync admission.
      final created = <String, Object?>{
        'room': room,
        'anchor': old,
        'cursor': null,
      };
      _gaps.add(created);
      await save(_state());
      return created;
    }

    if (limited || !_active()) gap = await ensureGap();
    if (!_active()) return;
    if (!await append(page.rows)) {
      await ensureGap();
      full = true;
      onFull?.call();
      return;
    }
    if (!_active() || allowed?.call() == false || !await recordPage(page)) {
      await ensureGap();
      return;
    }
    if (_tips.length >= 4096 && !_tips.containsKey(room)) return;
    _tips[room] = latest;
    if (gap != null && previousBatch != null && previousBatch.length <= 4096) {
      gap['cursor'] = previousBatch;
    }
    await save(_state());
  });

  /// At most one 100-event page per scheduler tick. Manual downloads, background
  /// transitions and cache limits prevent further requests, not just UI updates.
  Future<void> tick() => _serial(() async {
    if (!_active() || full || _gaps.isEmpty) return;
    final generation = _generation;
    bool active() => _active() && generation == _generation;
    final gap = _gaps.firstWhere((g) => g['blocked'] != true, orElse: () => {});
    if (gap.isEmpty) return;
    final room = gap['room'] as String, anchor = gap['anchor'] as String;
    final cursor = gap['cursor'] as String?;
    late final HistoryDownloadPage page;
    try {
      page = await fetch(room, cursor, anchor, active);
    } catch (_) {
      // One inaccessible room must not starve catch-up in every other room.
      if (!_closed) {
        _gaps.remove(gap);
        _gaps.add(gap);
      }
      rethrow;
    }
    if (!active()) return;
    if (!await append(page.rows)) {
      full = true;
      onFull?.call();
      return;
    }
    if (!active() || !await recordPage(page) || !active()) return;
    full = false;
    if (page.eventIds.contains(anchor)) {
      _gaps.remove(gap);
    } else if (page.nextCursor == null ||
        page.nextCursor == cursor ||
        (gap['seen'] as List? ?? []).contains(page.nextCursor)) {
      // Inaccessible history is not complete history. Preserve the unresolved
      // gap, without repeatedly walking an unreachable history boundary.
      gap['blocked'] = true;
    } else {
      if (page.nextCursor!.length > 4096) {
        throw StateError('Invalid history cursor');
      }
      gap['cursor'] = page.nextCursor;
      gap['seen'] = [
        ...(gap['seen'] as List? ?? []),
        page.nextCursor,
      ].reversed.take(8).toList().reversed.toList();
    }
    await save(_state());
  });

  Future<void> reset() {
    _generation++;
    return _serial(() async {
      _tips.clear();
      _gaps.clear();
      full = false;
      await save(null);
    });
  }

  void capacityChanged() {
    full = false;
  }

  void dispose() {
    _closed = true;
  }
}
