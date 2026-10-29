import 'dart:async';
import 'package:deltiecord/services/settings_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('debounces and serializes only latest pending settings', (
    tester,
  ) async {
    final values = <String>[];
    final writer = SettingsWriter<String>(
      write: (v) async => values.add(v),
      changed: () {},
    );
    writer.request('old');
    writer.request('new');
    await tester.pump(const Duration(milliseconds: 350));
    expect(values, ['new']);
    expect(writer.pending, null);
    writer.dispose();
  });
  test(
    'reset invalidates old queue and does not block a replacement account',
    () async {
      final old = Completer<void>();
      final started = Completer<void>();
      final values = <String>[];
      final writer = SettingsWriter<String>(
        write: (v) async {
          values.add(v);
          if (v == 'old') {
            started.complete();
            await old.future;
          }
        },
        changed: () {},
      );
      writer.request('old');
      final first = writer.flush();
      await started.future;
      writer.request('stale queued');
      final stale = writer.flush();
      writer.reset();
      writer.request('next account');
      await writer.flush();
      expect(values, ['old', 'next account']);
      expect(writer.pending, null);
      old.complete();
      await first;
      await stale;
      expect(values, ['old', 'next account']);
      writer.dispose();
    },
  );
  test(
    'failed write retains pending choice and disposal prevents later work',
    () async {
      var attempts = 0;
      final writer = SettingsWriter<String>(
        write: (_) async {
          attempts++;
          throw StateError('offline');
        },
        changed: () {},
      );
      writer.request('kept');
      await writer.flush();
      expect(writer.pending, 'kept');
      writer.dispose();
      writer.request('discarded');
      await writer.flush();
      expect(attempts, 1);
      expect(writer.pending, null);
    },
  );
}
