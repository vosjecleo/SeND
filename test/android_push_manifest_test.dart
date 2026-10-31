import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keyboard geometry reads cannot trigger another Android inset layout',
    () {
      final source = File(
        'android/app/src/main/kotlin/net/deltie/deltiecord/MainActivity.kt',
      ).readAsStringSync();
      final branch = source
          .split('call.method == "keyboardGeometry"')
          .last
          .split('call.method == "keyboardVisible"')
          .first;
      expect(branch, contains('keyboardGeometry?.snapshot()'));
      expect(branch, isNot(contains('.refresh(')));
      expect(branch, isNot(contains('requestApplyInsets')));
      expect(
        source,
        contains('keyboardGeometry?.refresh(resetAnimation = true)'),
      );
    },
  );

  // Configuration is parsed by packaging/test_android_configuration.py. These
  // source guards remain until Android instrumentation covers the native limits.
  test('Android bounds incoming shared media before reading it', () {
    final activity = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/MainActivity.kt',
    ).readAsStringSync();

    expect(activity, contains('MAX_SHARED_ITEM_BYTES'));
    expect(activity, contains('MAX_SHARED_TOTAL_BYTES'));
    expect(activity, contains('uris.size > 20'));
    expect(activity, contains('MAX_SHARED_TOTAL_BYTES = 256 * 1024 * 1024'));
    expect(activity, contains('return mapOf("error"'));
  });

  test('background push decrypts locally into bounded rich notifications', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final receiver = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushService.kt',
    ).readAsStringSync();
    final publisher = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordNotificationPublisher.kt',
    ).readAsStringSync();
    final worker = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordPushWorker.kt',
    ).readAsStringSync();
    final actionReceiver = File(
      'android/app/src/main/kotlin/net/deltie/deltiecord/'
      'DeltiecordNotificationActionReceiver.kt',
    ).readAsStringSync();

    expect(
      publisher,
      contains('.setContentText(latest.optString("body", "New message"))'),
    );
    expect(receiver, isNot(contains('New Matrix activity')));
    expect(receiver, isNot(contains('showPlaceholder')));
    expect(receiver, contains('sender_display_name'));
    expect(receiver, contains('room_name'));
    expect(receiver, contains('event_id'));
    expect(receiver, contains('DeltiecordPushWorker.enqueue'));
    expect(worker, contains('deltiecordPushBackgroundMain'));
    expect(worker, contains('resolveNotification'));
    expect(worker, contains('NonCancellable + Dispatchers.Main'));
    expect(worker, contains('releaseOwnedEngine(engine)'));
    expect(worker, contains('"shutdown"'));
    expect(publisher, contains('Notification.MessagingStyle'));
    expect(publisher, contains('setData(mime, uri)'));
    expect(
      publisher,
      contains('Build.VERSION.SDK_INT < Build.VERSION_CODES.P'),
    );
    expect(publisher, contains('R.mipmap.ic_launcher_round'));
    expect(publisher, contains('ALERT_COOLDOWN_MS'));
    expect(publisher, contains('setShortcutId(shortcutId)'));
    expect(worker, contains('cancelBackgroundWorkNotification'));
    expect(worker, contains('NetworkType.CONNECTED'));
    expect(worker, contains('BackoffPolicy.EXPONENTIAL'));
    expect(worker, contains('ExistingWorkPolicy.REPLACE'));
    expect(worker, contains('event_not_resolved_attempt_'));
    expect(publisher, contains('RemoteInput.Builder'));
    expect(publisher, contains('"reply", mutable = true'));
    expect(publisher, contains('"read", "Mark read"'));
    expect(publisher, contains('"mute", "Mute"'));
    expect(actionReceiver, contains('DeltiecordPushWorker.enqueueAction'));
    expect(worker, contains('performNotificationAction'));
    expect(worker, contains('reconcilePusher'));
    expect(worker, contains('PeriodicWorkRequestBuilder'));
    expect(worker, contains('ExistingPeriodicWorkPolicy.UPDATE'));
    expect(worker, contains('schedulePusherVerification'));
    expect(worker, contains('enqueuePusherReconciliation'));
    expect(receiver, contains('last_pusher_verification_ms'));
    expect(receiver, contains('last_endpoint_rotation_ms'));
    expect(worker, contains('suppressed_active_desktop'));
    expect(worker, isNot(contains('UnifiedPush.register(')));
    expect(receiver, contains('DeltiecordPushWakeService.start'));
    expect(manifest, contains('android:name=".DeltiecordPushWakeService"'));
  });
}
