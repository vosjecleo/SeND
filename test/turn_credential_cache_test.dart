import 'dart:async';
import 'package:deltiecord/matrix/refreshing_voip.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

TurnServerCredentials credentials(String name, {int ttl = 3600}) =>
    TurnServerCredentials(
      password: 'test-only',
      ttl: ttl,
      uris: [Uri.parse('turn:example.invalid:3478')],
      username: name,
    );

void main() {
  test('refreshes before TURN expiry, not once per login', () async {
    var now = DateTime.utc(2026);
    var requests = 0;
    final cache = TurnCredentialCache(
      () async => credentials('${++requests}'),
      now: () => now,
    );
    expect((await cache.getServers()).single['username'], '1');
    now = now.add(const Duration(minutes: 50));
    expect((await cache.getServers()).single['username'], '1');
    now = now.add(const Duration(minutes: 5));
    expect((await cache.getServers()).single['username'], '2');
    expect(requests, 2);
  });
  test('coalesces concurrent peers requesting credentials', () async {
    var requests = 0;
    final pending = Completer<TurnServerCredentials>();
    final cache = TurnCredentialCache(() {
      requests++;
      return pending.future;
    });
    final first = cache.getServers();
    final second = cache.getServers();
    pending.complete(credentials('shared'));
    expect(await first, await second);
    expect(requests, 1);
  });
  test(
    'failed refresh never hands out expired credentials and can retry',
    () async {
      var now = DateTime.utc(2026);
      var failing = false;
      final cache = TurnCredentialCache(() async {
        if (failing) throw StateError('unavailable');
        return credentials('test', ttl: 10);
      }, now: () => now);
      await cache.getServers();
      now = now.add(const Duration(seconds: 11));
      failing = true;
      await expectLater(cache.getServers(), throwsStateError);
      failing = false;
      expect(await cache.getServers(), isNotEmpty);
    },
  );
}
