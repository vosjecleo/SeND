import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/preference_scopes.dart';
import 'package:deltiecord/services/device_preferences_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'legacy choices seed once, remote changes do not replace device choices',
    () {
      final legacy = <String, Object?>{
        'preferred_audio_input': 'old-mic',
        'notification_sound': false,
        'theme_mode': 'dark',
        'send_read_receipts': false,
      };
      final local = PreferenceScopes.migrateDevice(legacy);
      final merged = PreferenceScopes.overlay(
        {
          ...legacy,
          'preferred_audio_input': 'other-device-mic',
          'notification_sound': true,
          'preferred_camera': 'new-remote-camera',
          'theme_mode': 'light',
        },
        local,
        'android',
      );
      expect(merged['preferred_audio_input'], 'old-mic');
      expect(merged['notification_sound'], false);
      expect(merged['preferred_camera'], null);
      expect(merged['theme_mode'], 'light');
      expect(merged['send_read_receipts'], false);
    },
  );

  test(
    'platform changes do not overwrite another platform or legacy migration seeds',
    () {
      final existing = <String, Object?>{
        'preferred_camera': 'legacy-camera',
        'video_compression': 'balanced',
        'platform_preferences': {
          'windows': {'video_compression': 'original'},
        },
        'unknown_future_field': 'retained',
      };
      final published = PreferenceScopes.accountPayload({
        'preferred_camera': 'android-camera',
        'video_compression': 'small',
        'notification_sound': false,
        'share_presence': false,
      }, existing);
      final android = PreferenceScopes.platformPayload({
        'video_compression': 'small',
      }, null);
      expect(published['preferred_camera'], 'legacy-camera');
      expect(published['notification_sound'], null);
      expect(published['video_compression'], 'balanced');
      expect(published['share_presence'], false);
      expect(published['unknown_future_field'], 'retained');
      expect(
        PreferenceScopes.overlay(
          published,
          null,
          'windows',
        )['video_compression'],
        'original',
      );
      expect(
        PreferenceScopes.overlay(
          published,
          null,
          'android',
          platformSettings: android,
        )['video_compression'],
        'small',
      );
      expect(
        PreferenceScopes.overlay(published, null, 'linux')['video_compression'],
        'balanced',
      );
    },
  );

  test('appearance sync never replaces local geometry or window chrome', () {
    const local = AppPreferences(
      roomPanelWidth: 333,
      sidePanelWidth: 299,
      showNativeTitleBar: false,
    );
    final synced = PreferenceScopes.keepDeviceLayout(
      const AppPreferences(themeMode: DeltiecordThemeMode.light),
      local,
    );
    expect(synced.roomPanelWidth, 333);
    expect(synced.sidePanelWidth, 299);
    expect(synced.showNativeTitleBar, false);
    expect(synced.themeMode, DeltiecordThemeMode.light);
  });

  test(
    'capture includes every device key but no appearance sync/privacy switches',
    () {
      final values = PreferenceScopes.captureDevice(const AppPreferences());
      expect(values.keys.toSet(), PreferenceScopes.deviceKeys);
      expect(values.containsKey('sync_appearance'), false);
      expect(values.containsKey('send_read_receipts'), false);
      expect(
        PreferenceScopes.deviceKeys.intersection(PreferenceScopes.platformKeys),
        isEmpty,
      );
    },
  );

  test(
    'local store survives reopen and isolates accounts, queues writes',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = DevicePreferencesStore();
      expect(await store.load('@a:test'), isNull);
      final first = PreferenceScopes.captureDevice(
        const AppPreferences(preferredCameraId: 'one'),
      );
      final second = PreferenceScopes.captureDevice(
        const AppPreferences(preferredCameraId: 'two'),
      );
      await Future.wait([
        store.save('@a:test', first),
        store.save('@a:test', second),
      ]);
      expect(
        (await DevicePreferencesStore().load('@a:test'))?['preferred_camera'],
        'two',
      );
      expect(await store.load('@b:test'), isNull);
    },
  );
}
