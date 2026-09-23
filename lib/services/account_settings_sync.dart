import 'dart:async';

/// A completed SDK sync attempt is not necessarily a successful sync: the SDK
/// reports network failures on its status stream rather than throwing them.
Future<void> waitForAccountSettings({
  required Future<dynamic>? firstAttempt,
  required bool Function() isHydrated,
  required Future<dynamic> Function() nextSuccessfulSync,
  Duration timeout = const Duration(seconds: 45),
}) async {
  Future<void> wait() async {
    await firstAttempt;
    if (!isHydrated()) await nextSuccessfulSync();
    if (!isHydrated()) {
      throw StateError('Account settings have not finished synchronizing.');
    }
  }

  await wait().timeout(timeout);
}
