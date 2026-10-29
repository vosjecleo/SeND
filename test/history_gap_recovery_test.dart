import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/history_gap_recovery.dart';
import 'package:deltiecord/services/history_download.dart';

HistoryDownloadPage page(List<String> ids, {String? cursor}) =>
    HistoryDownloadPage(
      rows: [
        for (final id in ids) {'id': id, 'room': '!r:test', 'body': 'text'},
      ],
      nextCursor: cursor,
      checked: ids.length,
      eventIds: ids,
    );

class Harness {
  Map<String, Object?>? saved;
  bool enabled = true, capacity = true, bookkeeping = true;
  final calls = <String?>[];
  final indexed = <String>{};
  late Future<HistoryDownloadPage> Function(String?) response;
  HistoryGapRecovery create() => HistoryGapRecovery(
    load: () async => saved,
    save: (state) async => saved = state == null
        ? null
        : Map<String, Object?>.from(jsonDecode(jsonEncode(state)) as Map),
    canRun: () => enabled,
    append: (rows) async {
      if (!capacity) return false;
      indexed.addAll(rows.map((row) => row['id'] as String));
      return true;
    },
    recordPage: (_) async => bookkeeping,
    fetch: (room, cursor, anchor, active) async {
      expect(room, '!r:test');
      expect(anchor, r'$old');
      calls.add(cursor);
      return response(cursor);
    },
  );
}

void main() {
  test('reset cancels an in-flight page before it reaches the index', () async {
    final h = Harness();
    final job = h.create();
    await job.open();
    await job.observe('!r:test', page([r'$old']), limited: false);
    await job.observe('!r:test', page([r'$new']), limited: true);
    final gate = Completer<HistoryDownloadPage>();
    h.response = (_) => gate.future;
    final work = job.tick();
    await Future<void>.delayed(Duration.zero);
    final reset = job.reset();
    gate.complete(page([r'$middle'], cursor: 'later'));
    await work;
    await reset;
    expect(h.indexed, isNot(contains(r'$middle')));
    expect(h.saved, null);
    await job.observe(
      '!r:test',
      page([r'$stale']),
      limited: false,
      allowed: () => false,
    );
    expect(h.indexed, isNot(contains(r'$stale')));
  });
  test(
    'new rooms establish a baseline without downloading lifetime history',
    () async {
      final h = Harness();
      final recovery = h.create();
      await recovery.open();
      await recovery.observe(
        '!r:test',
        page([r'$old']),
        limited: true,
        previousBatch: 'older',
      );
      await recovery.tick();
      expect(recovery.pending, 0);
      expect(h.calls, isEmpty);
      expect(h.saved!['tips'], {'!r:test': r'$old'});
    },
  );
  test(
    'limited sync walks to the prior event ID, persists each admitted page, and resumes',
    () async {
      final h = Harness();
      var recovery = h.create();
      await recovery.open();
      await recovery.observe('!r:test', page([r'$old']), limited: false);
      await recovery.observe(
        '!r:test',
        page([r'$new']),
        limited: true,
        previousBatch: 'before-new',
      );
      expect(recovery.pending, 1);
      h.response = (_) async => page([r'$middle'], cursor: 'next');
      await recovery.tick();
      expect(h.calls, ['before-new']);
      recovery.dispose();
      recovery = h.create();
      await recovery.open();
      h.response = (_) async => page([r'$old']);
      await recovery.tick();
      expect(h.calls, ['before-new', 'next']);
      expect(recovery.pending, 0);
      expect(h.indexed, containsAll([r'$new', r'$middle', r'$old']));
    },
  );
  test('quota and failed bookkeeping do not advance a cursor', () async {
    final h = Harness();
    final job = h.create();
    await job.open();
    await job.observe('!r:test', page([r'$old']), limited: false);
    await job.observe(
      '!r:test',
      page([r'$new']),
      limited: true,
      previousBatch: 'start',
    );
    h.response = (_) async => page([r'$middle'], cursor: 'next');
    h.capacity = false;
    await job.tick();
    expect(job.full, true);
    expect((h.saved!['gaps'] as List).single['cursor'], 'start');
    await job.tick();
    expect(h.calls.length, 1);
    job.capacityChanged();
    h.capacity = true;
    h.bookkeeping = false;
    await job.tick();
    expect((h.saved!['gaps'] as List).single['cursor'], 'start');
  });
  test(
    'background and manual work defer catch-up; inaccessible anchors stay unresolved',
    () async {
      final h = Harness();
      final job = h.create();
      await job.open();
      await job.observe('!r:test', page([r'$old']), limited: false);
      h.enabled = false;
      await job.observe('!r:test', page([r'$new']), limited: false);
      await job.tick();
      expect(h.calls, isEmpty);
      expect(job.pending, 1);
      h.enabled = true;
      h.response = (_) async => page([r'$middle']);
      await job.tick();
      expect(job.pending, 1);
      await job.tick();
      expect(h.calls.length, 1);
      expect((h.saved!['gaps'] as List).single['blocked'], true);
    },
  );
  test('background transition during fetch keeps the saved cursor', () async {
    final h = Harness();
    final job = h.create();
    await job.open();
    await job.observe('!r:test', page([r'$old']), limited: false);
    await job.observe(
      '!r:test',
      page([r'$new']),
      limited: true,
      previousBatch: 'start',
    );
    final gate = Completer<HistoryDownloadPage>();
    h.response = (_) => gate.future;
    final work = job.tick();
    await Future<void>.delayed(Duration.zero);
    h.enabled = false;
    gate.complete(page([r'$old']));
    await work;
    expect(job.pending, 1);
    expect((h.saved!['gaps'] as List).single['cursor'], 'start');
    await job.reset();
    expect(h.saved, null);
  });
}
