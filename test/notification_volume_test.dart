import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/notification_volume.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.windows,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform starts existing and new accounts at 20%, then keeps edits',
      () {
        debugDefaultTargetPlatformOverride = platform;
        expect(const AppPreferences().notificationVolume, .2);
        expect(readNotificationVolume(null), .2);
        expect(readNotificationVolume({'notification_volume': 1}), .2);
        expect(readNotificationVolume({'notification_volume': .6}), .2);
        expect(readNotificationVolume({'desktop_notification_volume': .4}), .4);
        expect(readNotificationVolume({'desktop_notification_volume': 0}), 0);
        expect(notificationVolumeSettingKey, 'desktop_notification_volume');
        expect(
          const AppPreferences()
              .copyWith(notificationVolume: .7)
              .notificationVolume,
          .7,
        );
      },
    );
  }
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform keeps its existing volume and default', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(const AppPreferences().notificationVolume, 1);
      expect(
        readNotificationVolume({
          'notification_volume': .8,
          'desktop_notification_volume': .2,
        }),
        .8,
      );
      expect(readNotificationVolume(null), 1);
      expect(notificationVolumeSettingKey, 'notification_volume');
    });
  }
}
