import 'package:deltiecord/services/settings_echo_guard.dart';
import 'dart:async';

import 'package:deltiecord/services/account_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'cached or successfully synced settings do not require another sync',
    () async {
      await waitForAccountSettings(
        firstAttempt: Future<void>.value(),
        isHydrated: () => true,
        nextSuccessfulSync: () => throw StateError('Unexpected sync wait'),
      );
    },
  );

  test('failed first attempt does not expose writable defaults', () async {
    var hydrated = false;
    var completed = false;
    final sync = Completer<void>();
    final ready = waitForAccountSettings(
      firstAttempt: Future<void>.value(),
      isHydrated: () => hydrated,
      nextSuccessfulSync: () => sync.future,
    ).then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    hydrated = true;
    sync.complete();
    await ready;
    expect(completed, isTrue);
  });

  test('missing settings fail closed within a bounded wait', () async {
    await expectLater(
      waitForAccountSettings(
        firstAttempt: null,
        isHydrated: () => false,
        nextSuccessfulSync: () => Completer<void>().future,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('late settings echoes cannot replace local choices', () {
    final guard = SettingsEchoGuard();
    guard.expect({'theme': 'light'}, {'theme': 'dark'});
    guard.expect({'theme': 'light'}, {'theme': 'night'});
    expect(guard.accepts({'theme': 'light'}), isFalse);
    expect(guard.accepts({'theme': 'dark'}), isFalse);
    expect(guard.accepts({'theme': 'night'}), isTrue);
    expect(guard.accepts({'theme': 'light'}), isTrue);
    guard.expect({'theme': 'light'}, {'theme': 'dark'});
    expect(
      guard.accepts({'theme': 'gray'}),
      isTrue,
      reason: 'Allow a new edit from another device',
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();
}
