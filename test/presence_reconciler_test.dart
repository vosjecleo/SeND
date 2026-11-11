import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:deltiecord/services/presence_reconciler.dart';

CachedPresence value(String id, PresenceType state) => CachedPresence(
  state,
  const Duration(days: 2).inMilliseconds,
  null,
  false,
  id,
);

class Fixture {
  Fixture({int concurrency = 4, int pending = 32, int entries = 4096}) {
    reader = PresenceReconciler(
      fetch: (id) async {
        requests.add(id);
        active++;
        if (active > peak) peak = active;
        try {
          return await (handler?.call(id) ??
              Future.value(value(id, PresenceType.offline)));
        } finally {
          active--;
        }
      },
      read: (id) => cache[id],
      publish: (id, presence) {
        published.add(id);
        cache[id] = presence;
      },
      now: () => time,
      concurrency: concurrency,
      maximumPending: pending,
      maximumEntries: entries,
    );
  }
  late PresenceReconciler reader;
  var time = DateTime.utc(2026, 11, 10);
  final cache = <String, CachedPresence>{};
  final requests = <String>[], published = <String>[];
  int active = 0, peak = 0;
  Future<CachedPresence> Function(String)? handler;
}

void main() {
  test(
    'a stale SDK value is repaired, then fresh checks are throttled',
    () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      f.cache['a'] = value('a', PresenceType.online);
      expect((await f.reader.refresh('a'))!.presence, PresenceType.offline);
      await f.reader.refresh('a');
      expect(f.requests, ['a']);
      f.time = f.time.add(const Duration(minutes: 1));
      await f.reader.refresh('a');
      expect(f.requests, ['a', 'a']);
    },
  );
  test(
    'a recent sync is authoritative; explicit refresh can query again',
    () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      f.cache['a'] = value('a', PresenceType.online);
      f.reader.observeSync('a');
      await f.reader.refresh('a');
      expect(f.requests, isEmpty);
      await f.reader.refresh('a', force: true);
      expect(f.requests, ['a']);
    },
  );
  test(
    'a newer sync beats an in-flight response, even before the sync callback',
    () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      final gate = Completer<CachedPresence>();
      f.handler = (_) => gate.future;
      f.cache['a'] = value('a', PresenceType.online);
      final pending = f.reader.refresh('a');
      final newer = value('a', PresenceType.offline);
      f.cache['a'] = newer;
      gate.complete(value('a', PresenceType.online));
      await pending;
      expect(f.cache['a'], same(newer));
      expect(f.published, isEmpty);
    },
  );
  test('sync freshness prevents a queued redundant request', () async {
    final f = Fixture(concurrency: 1);
    addTearDown(f.reader.dispose);
    final gate = Completer<CachedPresence>();
    f.handler = (id) => gate.future;
    final first = f.reader.refresh('a');
    final second = f.reader.refresh('b');
    f.cache['b'] = value('b', PresenceType.online);
    f.reader.observeSync('b');
    gate.complete(value('a', PresenceType.offline));
    await Future.wait([first, second]);
    expect(f.requests, ['a']);
  });
  test(
    'duplicates coalesce and both active and queued work are bounded',
    () async {
      final f = Fixture(concurrency: 2, pending: 4);
      addTearDown(f.reader.dispose);
      final gate = Completer<void>();
      f.handler = (id) async {
        await gate.future;
        return value(id, PresenceType.offline);
      };
      final first = f.reader.refresh('a');
      expect(f.reader.refresh('a'), same(first));
      final futures = [
        first,
        for (final id in ['b', 'c', 'd', 'e', 'f']) f.reader.refresh(id),
      ];
      expect(f.requests, ['a', 'b']);
      gate.complete();
      await Future.wait(futures);
      expect(f.peak, 2);
      expect(f.requests, ['a', 'b', 'c', 'd']);
    },
  );
  test(
    'network failures keep last known state and back off without claiming freshness',
    () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      f.cache['a'] = value('a', PresenceType.online);
      f.handler = (_) async => throw StateError('Connection lost');
      expect((await f.reader.refresh('a'))!.presence, PresenceType.online);
      await f.reader.refresh('a', force: true);
      expect(f.requests.length, 1);
      f.time = f.time.add(const Duration(seconds: 30));
      f.handler = null;
      await f.reader.refresh('a');
      expect(f.cache['a']!.presence, PresenceType.offline);
    },
  );
  test('rate-limit retry_after is respected', () async {
    final f = Fixture();
    addTearDown(f.reader.dispose);
    f.handler = (_) async => throw MatrixException.fromJson({
      'errcode': 'M_LIMIT_EXCEEDED',
      'retry_after_ms': 120000,
    });
    await f.reader.refresh('a');
    f.time = f.time.add(const Duration(minutes: 1));
    await f.reader.refresh('a');
    expect(f.requests.length, 1);
    f.time = f.time.add(const Duration(minutes: 1));
    f.handler = null;
    await f.reader.refresh('a');
    expect(f.requests.length, 2);
  });
  test(
    'an unsupported presence API retains sync state and backs off',
    () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      f.cache['a'] = value('a', PresenceType.online);
      f.handler = (_) async => throw MatrixException(
        http.Response('{"errcode":"M_UNRECOGNIZED"}', 404),
      );
      await f.reader.refresh('a');
      f.time = f.time.add(const Duration(minutes: 5));
      await f.reader.refresh('a');
      expect(f.requests, ['a']);
      expect(f.cache['a']!.presence, PresenceType.online);
    },
  );
  for (final status in [403, 404]) {
    test('server $status hides previously visible presence', () async {
      final f = Fixture();
      addTearDown(f.reader.dispose);
      f.cache['a'] = value('a', PresenceType.online);
      f.handler = (_) async => throw MatrixException(
        http.Response('{"errcode":"M_FORBIDDEN"}', status),
      );
      await f.reader.refresh('a');
      expect(f.cache['a']!.presence, PresenceType.offline);
    });
  }
  test(
    'resume/session invalidation cancels queued work and rejects old responses',
    () async {
      final f = Fixture(concurrency: 1);
      addTearDown(f.reader.dispose);
      final gate = Completer<CachedPresence>();
      f.handler = (_) => gate.future;
      final old = [f.reader.refresh('a'), f.reader.refresh('b')];
      f.reader.invalidate();
      await Future.wait(old);
      f.handler = null;
      final current = f.reader.refresh('a');
      gate.complete(value('a', PresenceType.online));
      await current;
      expect(f.requests, ['a', 'a']);
      expect(f.cache['a']!.presence, PresenceType.offline);
    },
  );
  test(
    'dispose completes callers without issuing queued reads or publishing late results',
    () async {
      final f = Fixture(concurrency: 1);
      final gate = Completer<CachedPresence>();
      f.handler = (_) => gate.future;
      final work = [f.reader.refresh('a'), f.reader.refresh('b')];
      f.reader.dispose();
      expect(await Future.wait(work), [null, null]);
      gate.complete(value('a', PresenceType.online));
      await Future<void>.delayed(Duration.zero);
      expect(f.requests, ['a']);
      expect(f.published, isEmpty);
    },
  );
  test('freshness bookkeeping has bounded retention', () async {
    final f = Fixture(concurrency: 1, pending: 2, entries: 2);
    addTearDown(f.reader.dispose);
    for (final id in ['a', 'b', 'c']) {
      await f.reader.refresh(id);
    }
    await f.reader.refresh('c');
    expect(f.requests.length, 3);
    await f.reader.refresh('a');
    expect(f.requests.length, 4);
  });
}
