import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/device_appearance_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('timeline avatar animation defaults off and survives local storage', () {
    const defaults = AppPreferences();
    expect(defaults.animateTimelineAvatars, isFalse);
    final snapshot = DeviceAppearanceSnapshot.capture(
      defaults.copyWith(animateTimelineAvatars: true),
    );
    final restored = DeviceAppearanceSnapshot.fromJson(snapshot.json);
    expect(restored.applyTo(defaults).animateTimelineAvatars, isTrue);
    final old = Map<String, Object?>.from(snapshot.json)
      ..remove('animate_timeline_avatars');
    expect(
      DeviceAppearanceSnapshot.fromJson(old).animateTimelineAvatars,
      isFalse,
    );
  });
  test('device appearance replaces only visual preferences', () {
    const account = AppPreferences(
      themeMode: DeltiecordThemeMode.light,
      notificationSound: false,
      sendReadReceipts: false,
    );
    const local = AppPreferences(
      themeMode: DeltiecordThemeMode.dark,
      fontScale: 1.2,
      notificationSound: true,
      sendReadReceipts: true,
    );

    final merged = DeviceAppearanceSnapshot.capture(local).applyTo(account);

    expect(merged.themeMode, DeltiecordThemeMode.dark);
    expect(merged.fontScale, 1.2);
    expect(merged.syncAppearance, isFalse);
    expect(merged.notificationSound, isFalse);
    expect(merged.sendReadReceipts, isFalse);
  });
}
