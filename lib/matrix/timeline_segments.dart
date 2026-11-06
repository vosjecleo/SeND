import 'dart:async';
import 'dart:collection';
import 'package:matrix/matrix.dart';
// The SDK exposes Timeline.chunk but does not re-export its constructor type.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

/// A contiguous range, never a timestamp-sorted union of unrelated windows.
class MatrixTimelineSegment {
  MatrixTimelineSegment(this.id, this.timeline, {required this.live})
    : events = _reconcileLocalEchoes(timeline.events);
  final String id;
  Timeline timeline;
  List<Event> events;
  bool live;
  MatrixTimelineSegment? newer;
  int epoch = 0;
  int databaseOffset = 0;
  bool olderCursorAnchored = false;
  bool databaseExhausted = false, serverExhausted = false, loading = false;
}

/// Owns range identity independently of the SDK's mutable Timeline object.
/// Limited sync must not erase the viewed range or splice an old response into
/// a new live range. Inactive ranges remain available until the room closes.
class MatrixTimelineSegments {
  MatrixTimelineSegments(this.changed);
  final void Function() changed;
  final List<MatrixTimelineSegment> ranges = [];
  MatrixTimelineSegment? active, live;
  StreamSubscription<SyncUpdate>? _sync;
  StreamSubscription<Event>? _timelineUpdates, _historyUpdates;
  int _serial = 0;

  MatrixTimelineSegment? forTimeline(Timeline timeline) =>
      ranges.where((s) => identical(s.timeline, timeline)).firstOrNull;

  MatrixTimelineSegment adopt(Timeline timeline, {required bool isLive}) {
    final previousLive = live;
    // The SDK's limited-sync listener deletes retained rows. Range transitions
    // belong here instead; the normal event/reaction/decryption machinery stays
    // SDK-owned.
    timeline.roomSub?.cancel();
    timeline.roomSub = null;
    final segment = MatrixTimelineSegment(
      '${timeline.room.id}:${++_serial}',
      timeline,
      live: isLive,
    );
    segment.databaseOffset = timeline.events
        .where((e) => e.status.isSynced)
        .length;
    segment.databaseExhausted = !isLive;
    segment.olderCursorAnchored = !isLive;
    if (!isLive) segment.newer = live;
    ranges.add(segment);
    active = segment;
    if (isLive) {
      if (previousLive != null &&
          mergeOverlappingEvents(segment.events, previousLive.events) == null) {
        _replace(
          previousLive,
          previousLive.events,
          previousLive.timeline.chunk.prevBatch,
          previousLive.timeline.chunk.nextBatch,
          isLive: false,
        );
        previousLive.newer = segment;
      }
      live = segment;
    }
    _sync ??= timeline.room.client.onSync.stream.listen(_acceptSync);
    _timelineUpdates ??= timeline.room.client.onTimelineEvent.stream.listen(
      _knownUpdate,
    );
    _historyUpdates ??= timeline.room.client.onHistoryEvent.stream.listen(
      _knownUpdate,
    );
    return segment;
  }

  /// Unknown synced rows wait for the sync batch to establish continuity.
  /// Existing rows, decryptions and local echoes can update immediately.
  void refreshKnown(MatrixTimelineSegment segment) {
    final canonical = _reconcileLocalEchoes(segment.timeline.events);
    final raw = {for (final e in canonical) e.eventId: e};
    final transactions = {
      for (final e in canonical)
        if (e.transactionId != null)
          (e.roomId, e.senderId, e.transactionId!): e,
    };
    final refreshed = <Event>[];
    for (final event in segment.events) {
      final replacement =
          raw[event.eventId] ??
          transactions[(
            event.roomId,
            event.senderId,
            event.transactionId ?? event.eventId,
          )];
      if (replacement != null) {
        refreshed.add(_preferredEcho(event, replacement));
      } else if (event.redacted || event.status.isSynced) {
        refreshed.add(event);
      }
    }
    if (segment.live) {
      final ids = refreshed.map((e) => e.eventId).toSet();
      final local = canonical.where(
        (e) => !e.status.isSynced && !ids.contains(e.eventId),
      );
      segment.events = _reconcileLocalEchoes([...local, ...refreshed]);
    } else {
      segment.events = _reconcileLocalEchoes(refreshed);
    }
  }

  void appendRows(
    MatrixTimelineSegment segment,
    List<Event> page,
    Direction direction,
  ) {
    refreshKnown(segment);
    final combined = direction == Direction.b
        ? [...segment.events, ...page]
        : [...page, ...segment.events];
    segment.events = _reconcileLocalEchoes(combined);
    segment.timeline.events
      ..clear()
      ..addAll(segment.events);
    for (final event in page) {
      segment.timeline.addAggregatedEvent(event);
    }
  }

  void reconcile(MatrixTimelineSegment segment) {
    refreshKnown(segment);
    _joinProvenRanges(segment);
    changed();
  }

  void _knownUpdate(Event event) {
    var updated = false;
    for (final segment in ranges) {
      if (segment.timeline.room.id != event.roomId) continue;
      final index = segment.events.indexWhere(
        (e) => e.eventId == event.eventId,
      );
      if (index >= 0) {
        final previous = segment.events[index];
        if (!(previous.redacted && !event.redacted) &&
            !(previous.status.isSynced && !event.status.isSynced)) {
          segment.events[index] = event;
          final rawIndex = segment.timeline.events.indexWhere(
            (e) => e.eventId == event.eventId,
          );
          if (rawIndex >= 0) segment.timeline.events[rawIndex] = event;
          updated = true;
        }
      }
      final root = event.relationshipEventId;
      final relation = event.relationshipType;
      if (root != null &&
          relation != null &&
          segment.events.any((e) => e.eventId == root)) {
        segment.timeline.aggregatedEvents[root]?[relation]?.removeWhere(
          (e) => e.eventId == event.eventId,
        );
        segment.timeline.addAggregatedEvent(event);
        updated = true;
      }
      if (event.type == EventTypes.Redaction) {
        for (final target in segment.events.where(
          (e) => e.eventId == event.redacts,
        )) {
          target.setRedactionEvent(event);
          updated = true;
        }
        final removed = <Event>[
          for (final relations in segment.timeline.aggregatedEvents.values)
            for (final entries in relations.values)
              for (final target in entries)
                if (target.eventId == event.redacts) target,
        ];
        for (final target in removed) {
          // Another SDK timeline may already have cleared this shared event's
          // relation content. Remove by ID, not by its now-missing relation.
          for (final relations in segment.timeline.aggregatedEvents.values) {
            for (final entries in relations.values) {
              entries.removeWhere((e) => e.eventId == target.eventId);
            }
          }
          target.setRedactionEvent(event);
          updated = true;
        }
      }
    }
    if (updated) changed();
  }

  bool current(MatrixTimelineSegment segment, Timeline timeline, int epoch) =>
      ranges.contains(segment) &&
      identical(segment.timeline, timeline) &&
      segment.epoch == epoch;

  void _acceptSync(SyncUpdate update) {
    final room = active?.timeline.room ?? live?.timeline.room;
    if (room == null) return;
    final batch = update.rooms?.join?[room.id]?.timeline;
    if (batch == null ||
        (batch.events?.isEmpty != false && batch.limited != true)) {
      for (final s in ranges) {
        refreshKnown(s);
      }
      changed();
      return;
    }
    final previous = live;
    final incoming = (batch.events ?? <MatrixEvent>[]).reversed.map((wire) {
      // Reuse the SDK-decrypted event when available.
      return previous?.timeline.events
              .where((e) => e.eventId == wire.eventId)
              .firstOrNull ??
          Event.fromMatrixEvent(wire, room);
    }).toList();
    final connected = previous == null
        ? null
        : mergeOverlappingEvents(incoming, previous.events);
    if (previous != null && batch.limited != true) {
      if (connected != null) {
        previous.timeline.events
          ..clear()
          ..addAll(connected);
        previous.events = connected;
        for (final event in incoming) {
          previous.timeline.addAggregatedEvent(event);
        }
      } else {
        appendRows(previous, incoming, Direction.f);
      }
      reconcile(previous);
    } else if (previous != null && connected != null) {
      // The database's main fragment changed, even though overlap proves this
      // range is continuous. Its previous positional DB cursor is now invalid.
      _replace(
        previous,
        connected,
        previous.timeline.chunk.prevBatch,
        '',
        isLive: true,
      );
      previous.databaseExhausted = true;
      live = previous;
    } else {
      if (previous != null) {
        _replace(
          previous,
          previous.events,
          previous.timeline.chunk.prevBatch,
          previous.timeline.chunk.nextBatch,
          isLive: false,
        );
      }
      final head = MatrixTimelineSegment(
        '${room.id}:${++_serial}',
        _make(
          room,
          incoming,
          batch.prevBatch ?? room.prev_batch ?? '',
          '',
          true,
        ),
        live: true,
      );
      head.databaseExhausted = true;
      head.olderCursorAnchored = true;
      ranges.add(head);
      live = head;
      if (previous != null) previous.newer = head;
      if (active != head && active?.newer == null) active?.newer = head;
    }
    changed();
  }

  Timeline _make(
    Room room,
    List<Event> events,
    String older,
    String newer,
    bool isLive,
  ) {
    late final Timeline timeline;
    timeline = Timeline(
      room: room,
      chunk: TimelineChunk(
        events: List.of(events),
        prevBatch: older,
        nextBatch: newer,
      ),
      onUpdate: () {
        final segment = forTimeline(timeline);
        if (segment == null) return;
        refreshKnown(segment);
        changed();
      },
    );
    timeline.roomSub?.cancel();
    timeline.roomSub = null;
    if (!isLive) {
      timeline.allowNewEvent = false;
      timeline.isFragmentedTimeline = true;
    }
    return timeline;
  }

  void _replace(
    MatrixTimelineSegment segment,
    List<Event> events,
    String older,
    String newer, {
    required bool isLive,
  }) {
    final old = segment.timeline;
    events = _reconcileLocalEchoes(events);
    old.cancelSubscriptions();
    final replacement = _make(old.room, events, older, newer, isLive);
    _copyAggregates(old, replacement);
    segment.timeline = replacement;
    segment.events = List.of(events);
    segment.live = isLive;
    if (!isLive) segment.databaseExhausted = true;
    segment.epoch++;
    segment.loading = false;
  }

  void _copyAggregates(Timeline old, Timeline replacement) {
    for (final root in old.aggregatedEvents.entries) {
      for (final relation in root.value.entries) {
        final merged = {
          for (final e in relation.value) e.eventId: e,
          for (final e
              in replacement.aggregatedEvents[root.key]?[relation.key] ??
                  <Event>{})
            e.eventId: e,
        };
        (replacement.aggregatedEvents[root.key] ??= {})[relation.key] = merged
            .values
            .toSet();
      }
    }
  }

  /// A frozen former live range needs a forward token. Obtain context around
  /// its head and accept it only when it overlaps that retained range.
  Future<bool> loadBoundary(
    MatrixTimelineSegment segment,
    Direction direction,
  ) async {
    final source = segment.timeline;
    final epoch = segment.epoch;
    final synced = segment.events.where((e) => e.status.isSynced);
    final anchor = direction == Direction.b
        ? synced.lastOrNull
        : synced.firstOrNull;
    if (anchor == null) return false;
    // getTimeline(contextId) may return the main DB slice instead of actual
    // context, with no forward token. Request the boundary explicitly.
    final chunk = await source.room.getEventContext(anchor.eventId);
    if (!current(segment, source, epoch) ||
        !identical(active, segment) ||
        chunk == null) {
      return false;
    }
    final context = Timeline(room: source.room, chunk: chunk);
    context.cancelSubscriptions();
    final union = mergeOverlappingEvents(context.events, segment.events);
    if (union == null) return false;
    final older = direction == Direction.b
        ? chunk.prevBatch
        : source.chunk.prevBatch;
    final newer = direction == Direction.f
        ? chunk.nextBatch
        : source.chunk.nextBatch;
    _replace(segment, union, older, newer, isLive: segment.live);
    segment.databaseExhausted = true;
    if (direction == Direction.b) segment.olderCursorAnchored = true;
    _joinProvenRanges(segment);
    changed();
    return true;
  }

  void _joinProvenRanges(MatrixTimelineSegment segment) {
    for (final other in List.of(ranges)) {
      if (identical(segment, other)) continue;
      final union = mergeOverlappingEvents(segment.events, other.events);
      if (union == null) continue;
      if (identical(other, active) && !identical(segment, active)) {
        _joinProvenRanges(other);
        return;
      }
      final becameLive = segment.live || other.live;
      // Keep the oldest range's backward token. No timestamp comparison is
      // used to decide continuity or to position events.
      final last = union.lastOrNull?.eventId;
      final older = last == other.events.lastOrNull?.eventId
          ? other.timeline.chunk.prevBatch
          : segment.timeline.chunk.prevBatch;
      final newer = becameLive ? '' : segment.timeline.chunk.nextBatch;
      final unchanged =
          union.length == segment.events.length &&
          union.indexed.every(
            (e) => e.$2.eventId == segment.events[e.$1].eventId,
          );
      if (!unchanged) {
        segment.olderCursorAnchored = last == other.events.lastOrNull?.eventId
            ? other.olderCursorAnchored
            : segment.olderCursorAnchored;
        _replace(segment, union, older, newer, isLive: becameLive);
        segment.databaseExhausted = true;
      } else {
        segment.live = becameLive;
        if (becameLive) {
          segment.timeline.allowNewEvent = true;
          segment.timeline.chunk.nextBatch = '';
        }
        _copyAggregates(other.timeline, segment.timeline);
      }
      if (last == other.events.lastOrNull?.eventId) {
        segment.serverExhausted = other.serverExhausted;
        if (other.olderCursorAnchored) {
          segment.olderCursorAnchored = true;
          segment.timeline.chunk.prevBatch = other.timeline.chunk.prevBatch;
        }
      }
      final next = identical(segment.newer, other)
          ? other.newer
          : segment.newer;
      segment.newer = becameLive ? null : next;
      for (final s in ranges) {
        if (identical(s.newer, other)) s.newer = segment;
      }
      if (identical(active, other)) active = segment;
      if (identical(live, other) || becameLive) live = segment;
      other.timeline.cancelSubscriptions();
      ranges.remove(other);
    }
  }

  void select(MatrixTimelineSegment segment) {
    active = segment;
    changed();
  }

  void reachedLiveEnd(MatrixTimelineSegment segment) {
    final previous = live;
    final knownHead = previous?.events
        .where((e) => e.status.isSynced)
        .firstOrNull;
    if (previous != null &&
        !identical(previous, segment) &&
        knownHead != null &&
        !segment.events.any((e) => e.eventId == knownHead.eventId)) {
      // Sync advanced while this forward page was in flight. Its EOF is not
      // proof that the newly arrived head is connected to this range.
      segment.timeline.allowNewEvent = false;
      segment.timeline.chunk.nextBatch = '';
      segment.newer = previous;
      return;
    }
    if (previous != null && !identical(previous, segment)) {
      _replace(
        previous,
        previous.events,
        previous.timeline.chunk.prevBatch,
        previous.timeline.chunk.nextBatch,
        isLive: false,
      );
      previous.newer = segment;
    }
    segment.live = true;
    segment.newer = null;
    segment.timeline.allowNewEvent = true;
    segment.timeline.chunk.nextBatch = '';
    live = segment;
    changed();
  }

  void dispose() {
    _sync?.cancel();
    _timelineUpdates?.cancel();
    _historyUpdates?.cancel();
    _timelineUpdates = null;
    _historyUpdates = null;
    _sync = null;
    for (final segment in ranges) {
      segment.timeline.cancelSubscriptions();
    }
    ranges.clear();
    active = null;
    live = null;
  }
}

/// Stable topological union of overlapping server-ordered ranges. Disconnected
/// ranges and contradictory ordering stay separate. Never drop retained rows.
List<Event>? mergeOverlappingEvents(List<Event> first, List<Event> second) {
  final firstIds = first
      .where((e) => e.status.isSynced)
      .map((e) => e.eventId)
      .toSet();
  if (!second.any((e) => e.status.isSynced && firstIds.contains(e.eventId))) {
    return null;
  }
  final events = <String, Event>{};
  for (final event in [...second, ...first]) {
    final previous = events[event.eventId];
    events[event.eventId] = previous == null
        ? event
        : _preferredEcho(previous, event);
  }
  final priority = <String, int>{};
  for (final e in [...first, ...second]) {
    priority.putIfAbsent(e.eventId, () => priority.length);
  }
  final edges = <String, Set<String>>{};
  final incoming = {for (final id in events.keys) id: 0};
  for (final list in [first, second]) {
    String? previous;
    for (final e in list) {
      if (previous != null &&
          previous != e.eventId &&
          (edges[previous] ??= {}).add(e.eventId)) {
        incoming[e.eventId] = incoming[e.eventId]! + 1;
      }
      previous = e.eventId;
    }
  }
  final ready = SplayTreeSet<String>(
    (a, b) => priority[a]!.compareTo(priority[b]!),
  )..addAll(incoming.keys.where((id) => incoming[id] == 0));
  final result = <Event>[];
  while (ready.isNotEmpty) {
    final id = ready.first;
    ready.remove(id);
    result.add(events[id]!);
    for (final next in edges[id] ?? <String>{}) {
      incoming[next] = incoming[next]! - 1;
      if (incoming[next] == 0) ready.add(next);
    }
  }
  return result.length == events.length ? _reconcileLocalEchoes(result) : null;
}

/// Acknowledgements replace only their own local echoes, never distinct server
/// events. Keep the acknowledged row's server position, not the echo's position.
/// This runs after overlap checks: a transaction ID cannot prove continuity
/// between otherwise disconnected server ranges.
List<Event> _reconcileLocalEchoes(Iterable<Event> events) {
  final byId = <String, Event>{};
  for (final event in events) {
    final previous = byId[event.eventId];
    byId[event.eventId] = previous == null
        ? event
        : _preferredEcho(previous, event);
  }
  final acknowledged = {
    for (final event in byId.values)
      if (event.status.isSent && event.transactionId != null)
        (event.roomId, event.senderId, event.transactionId!),
  };
  final localPositions = <(String?, String, String), int>{};
  final result = <Event>[];
  for (final event in byId.values) {
    if (!event.status.isSent) {
      final identity = (
        event.roomId,
        event.senderId,
        event.transactionId ?? event.eventId,
      );
      if (acknowledged.contains(identity)) continue;
      final position = localPositions[identity];
      if (position != null) {
        result[position] = _preferredEcho(result[position], event);
        continue;
      }
      localPositions[identity] = result.length;
    }
    result.add(event);
  }
  return result;
}

Event _preferredEcho(Event previous, Event replacement) {
  if (previous.redacted) return previous;
  if (replacement.redacted) return replacement;
  if (previous.status.isSynced != replacement.status.isSynced) {
    return previous.status.isSynced ? previous : replacement;
  }
  if (previous.status.isSent != replacement.status.isSent) {
    return previous.status.isSent ? previous : replacement;
  }
  if (previous.type != EventTypes.Encrypted &&
      replacement.type == EventTypes.Encrypted) {
    return previous;
  }
  return replacement;
}
