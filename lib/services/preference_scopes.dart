import '../models/chat_models.dart';

/// Account data keeps privacy, appearance (when enabled), room behaviour and
/// reading preferences. Hardware IDs and alert choices belong to this device.
/// Performance/encoding and keyboard choices are shared only within a platform.
abstract final class PreferenceScopes {
  static const deviceKeys = {
    'notifications_enabled',
    'notification_sound',
    'notification_volume',
    'desktop_notification_volume',
    'notification_vibration',
    'notification_alert_cadence',
    'call_volume',
    'preferred_audio_input',
    'preferred_audio_output',
    'preferred_camera',
    'echo_cancellation',
    'noise_suppression',
    'auto_gain_control',
    'microphone_volume',
    'output_volume',
    'call_sound',
    'share_desktop_audio',
    'participant_volumes',
    'desktop_idle_minutes',
    'remember_window_state',
    'show_native_title_bar',
    'room_panel_width',
    'side_panel_width',
  };
  static const platformKeys = {
    'optimize_videos',
    'image_compression',
    'video_compression',
    'shortcut_bindings',
    'send_with_ctrl_enter',
    'enable_channel_drag_and_drop',
    'timeline_chunk_size',
    'timeline_chunk_cap',
    'mobile_font_scale',
    'desktop_font_scale',
  };

  static Map<String, Object?> captureDevice(AppPreferences p) => {
    'notifications_enabled': p.notificationsEnabled,
    'notification_sound': p.notificationSound,
    'notification_volume': p.notificationVolume,
    'desktop_notification_volume': p.notificationVolume,
    'notification_vibration': p.notificationVibration,
    'notification_alert_cadence': p.notificationAlertCadence.name,
    'call_volume': p.callVolume,
    'preferred_audio_input': p.preferredAudioInputId,
    'preferred_audio_output': p.preferredAudioOutputId,
    'preferred_camera': p.preferredCameraId,
    'echo_cancellation': p.echoCancellation,
    'noise_suppression': p.noiseSuppression,
    'auto_gain_control': p.autoGainControl,
    'microphone_volume': p.microphoneVolume,
    'output_volume': p.outputVolume,
    'call_sound': p.callSound,
    'share_desktop_audio': p.shareDesktopAudio,
    'participant_volumes': p.participantVolumes,
    'desktop_idle_minutes': p.desktopIdleMinutes,
    'remember_window_state': p.rememberWindowState,
    'show_native_title_bar': p.showNativeTitleBar,
    'room_panel_width': p.roomPanelWidth,
    'side_panel_width': p.sidePanelWidth,
  };

  /// Seed once from legacy account data without deleting it. A device which
  /// has not upgraded yet can still recover its old choices. Explicit nulls
  /// pin absent settings to their default rather than following later echoes.
  static Map<String, Object?> migrateDevice(Map<String, Object?>? account) => {
    for (final key in deviceKeys) key: account?[key],
  };

  static Map<String, Object?> overlay(
    Map<String, Object?>? account,
    Map<String, Object?>? device,
    String platform, {
    Map<String, Object?>? platformSettings,
  }) {
    final platforms = account?['platform_preferences'];
    final scoped =
        platformSettings ?? (platforms is Map ? platforms[platform] : null);
    return {
      ...?account,
      if (scoped is Map)
        for (final key in platformKeys)
          if (scoped.containsKey(key)) key: scoped[key],
      if (device != null)
        for (final key in deviceKeys) key: device[key],
    };
  }

  static Map<String, Object?> accountPayload(
    Map<String, Object?> full,
    Map<String, Object?>? previous,
  ) {
    return {
      // Keep old values as migration seeds, not as live settings.
      ...?previous,
      for (final entry in full.entries)
        if (!deviceKeys.contains(entry.key) &&
            !platformKeys.contains(entry.key))
          entry.key: entry.value,
      'preferences_scope_schema': 1,
    };
  }

  static Map<String, Object?> platformPayload(
    Map<String, Object?> full,
    Map<String, Object?>? previous,
  ) => {
    ...?previous,
    'schema': 1,
    for (final key in platformKeys)
      if (full.containsKey(key)) key: full[key],
  };

  static Map<String, Object?> syncedValues(Map<String, Object?> full) => {
    for (final entry in full.entries)
      if (!deviceKeys.contains(entry.key)) entry.key: entry.value,
  };

  static AppPreferences keepDeviceLayout(
    AppPreferences appearance,
    AppPreferences device,
  ) => appearance.copyWith(
    roomPanelWidth: device.roomPanelWidth,
    sidePanelWidth: device.sidePanelWidth,
    showNativeTitleBar: device.showNativeTitleBar,
  );
}
