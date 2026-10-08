import 'package:flutter/foundation.dart';

bool get _desktop => switch (defaultTargetPlatform) {
  TargetPlatform.linux ||
  TargetPlatform.macOS ||
  TargetPlatform.windows => true,
  _ => false,
};

double get defaultNotificationVolume => _desktop ? 0.2 : 1;

String get notificationVolumeSettingKey =>
    // The separate key resets existing desktop accounts once without changing
    // mobile volume. Later desktop adjustments survive subsequent syncs.
    _desktop ? 'desktop_notification_volume' : 'notification_volume';

double readNotificationVolume(Map<String, dynamic>? settings) =>
    (settings?[notificationVolumeSettingKey] as num?)?.toDouble().clamp(0, 1) ??
    defaultNotificationVolume;
