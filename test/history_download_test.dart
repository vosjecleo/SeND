import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/history_download.dart';

Map<String, Object?> row(String id) => {
  'id': id,
  'room': '!r:test',
  'time': 1,
  'sender': '@me:test',
  'kind': '',
  'body': 'message',
};

class Harness {
  Map<String, Object?>? saved;
  final writes = <String, Map<String, Object?>>{};
  final calls = <(String, String?)>[];
  int capacity = 100;
  bool enabled = true, saveFails = false;
  late Future<HistoryDownloadPage> Function(String, String?) page;
  HistoryDownload create() => HistoryDownload(
    fetch: (room, cursor) {
      calls.add((room, cursor));
      return page(room, cursor);
    },
    append: (rows) async {
      if ({...writes.keys, ...rows.map((r) => r['id'] as String)}.length >
          capacity) {
        return false;
      }
      for (final r in rows) {
        writes[r['id'] as String] = r;
      }
      return true;
    },
    load: () async => saved,
    save: (value) async {
      if (saveFails) throw StateError('private storage details');
      saved = value == null
          ? null
          : Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);
    },
    canRun: () => enabled,
    pageDelay: Duration.zero,
  );
}

void main() {
  test(
    'paginates every selected room, including empty advancing pages',
    () async {
      final h = Harness()
        ..page = (room, cursor) async {
          if (room == '!second:test') {
            return HistoryDownloadPage(
              rows: [row('c')],
              nextCursor: null,
              checked: 1,
            );
          }
          return switch (cursor) {
            null => HistoryDownloadPage(
              rows: [row('a')],
              nextCursor: 'a',
              checked: 2,
              unavailable: 1,
            ),
            'a' => const HistoryDownloadPage(
              rows: [],
              nextCursor: 'b',
              checked: 0,
            ),
            _ => HistoryDownloadPage(
              rows: [row('b')],
              nextCursor: null,
              checked: 1,
            ),
          };
        };
      final job = h.create();
      await job.open();
      await job.start(['!r:test', '!second:test']);
      await job.done;
      expect(job.status, HistoryDownloadStatus.complete);
      expect(job.completedRooms, 2);
      expect(job.checked, 4);
      expect(job.unavailable, 1);
      expect(h.writes.keys, unorderedEquals(['a', 'b', 'c']));
      expect(h.calls.length, 4);
      expect(jsonEncode(h.saved), isNot(contains('message')));
      job.dispose();
    },
  );

  test(
    'quota pauses before advancing cursor, and larger quota resumes the same page',
    () async {
      final h = Harness()..capacity = 1;
      h.page = (_, cursor) async => switch (cursor) {
        null => HistoryDownloadPage(
          rows: [row('a')],
          nextCursor: 'a',
          checked: 1,
        ),
        'a' => HistoryDownloadPage(
          rows: [row('b')],
          nextCursor: 'b',
          checked: 1,
        ),
        _ => const HistoryDownloadPage(rows: [], nextCursor: null, checked: 0),
      };
      final job = h.create();
      await job.start(['!r:test']);
      await job.done;
      expect(job.status, HistoryDownloadStatus.full);
      expect(job.checked, 1);
      expect(h.saved!['cursor'], 'a');
      expect(h.writes.keys, ['a']);
      job.dispose();
      final resumed = h.create();
      await resumed.open();
      expect(resumed.status, HistoryDownloadStatus.full);
      expect(
        h.calls.length,
        2,
        reason: 'Opening never automatically downloads.',
      );
      h.capacity = 2;
      await resumed.resume();
      await resumed.done;
      expect(h.calls.map((c) => c.$2), [null, 'a', 'a', 'b']);
      expect(resumed.status, HistoryDownloadStatus.complete);
      expect(h.writes.keys, ['a', 'b']);
      resumed.dispose();
    },
  );

  for (final close in [false, true]) {
    test(
      'a ${close ? 'disposed' : 'paused'} job ignores an in-flight page',
      () async {
        final gate = Completer<HistoryDownloadPage>();
        final h = Harness()..page = (_, _) => gate.future;
        final job = h.create();
        await job.start(['!r:test']);
        await Future<void>.delayed(Duration.zero);
        final guard = job.guardForCurrentRun();
        expect(guard(), true);
        if (close) {
          job.dispose();
        } else {
          job.pause();
        }
        expect(guard(), false);
        gate.complete(
          HistoryDownloadPage(
            rows: [row('ignore')],
            nextCursor: 'next',
            checked: 1,
          ),
        );
        await job.done;
        expect(h.writes, isEmpty);
        expect(h.saved!['cursor'], isNull);
        if (!close) {
          expect(job.status, HistoryDownloadStatus.paused);
          job.dispose();
        }
      },
    );
  }

  test(
    'repeated pagination cannot spin or silently claim complete coverage',
    () async {
      final h = Harness()
        ..page = (_, cursor) async => HistoryDownloadPage(
          rows: [row(cursor ?? 'first')],
          nextCursor: cursor == 'a' ? 'b' : 'a',
          checked: 1,
        );
      final job = h.create();
      await job.start(['!r:test']);
      await job.done;
      expect(job.status, HistoryDownloadStatus.error);
      expect(h.calls.length, 3);
      expect(job.completedRooms, 0);
      job.dispose();
    },
  );

  test(
    'network errors preserve resumable progress without exposing private errors',
    () async {
      final h = Harness()
        ..page = (_, _) async =>
            throw StateError('https://private/endpoint?token=secret');
      final job = h.create();
      await job.start(['!r:test']);
      await job.done;
      expect(job.status, HistoryDownloadStatus.error);
      expect(job.hasCheckpoint, true);
      expect(job.message, isNot(contains('secret')));
      expect(jsonEncode(h.saved), isNot(contains('secret')));
      job.dispose();
    },
  );

  test(
    'failed checkpoint save stops before making a network request',
    () async {
      final h = Harness()..saveFails = true;
      final job = h.create();
      await job.start(['!r:test']);
      expect(job.status, HistoryDownloadStatus.error);
      expect(h.calls, isEmpty);
      job.dispose();
    },
  );

  test(
    'disabled indexing and invalid saved state do not start network activity',
    () async {
      final h = Harness()..enabled = false;
      final job = h.create();
      await job.start(['!r:test']);
      expect(job.status, HistoryDownloadStatus.paused);
      expect(h.calls, isEmpty);
      job.dispose();
      h.saved = {'version': 1, 'rooms': 'invalid'};
      final invalid = h.create();
      await invalid.open();
      expect(invalid.status, HistoryDownloadStatus.error);
      expect(h.calls, isEmpty);
      invalid.dispose();
    },
  );
}
