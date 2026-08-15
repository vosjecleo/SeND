import 'dart:io';

import 'package:flutter/services.dart';

import '../models/chat_models.dart';

class DesktopWindowService {
  DesktopWindowService._();

  static const _channel = MethodChannel('net.deltie.deltiecord/window');
  static AppPreferences? _applied;

  static Future<void> apply(AppPreferences preferences) async {
    if (!Platform.isLinux || _sameWindowSettings(_applied, preferences)) return;
    _applied = preferences;
    try {
      await _channel.invokeMethod<void>('configure', {
        'showNativeTitleBar': preferences.showNativeTitleBar,
        'rememberWindowState': preferences.rememberWindowState,
      });
    } on MissingPluginException {
      // Widget tests and non-desktop targets do not register the GTK channel.
    }
  }

  static bool _sameWindowSettings(
    AppPreferences? previous,
    AppPreferences current,
  ) =>
      previous?.showNativeTitleBar == current.showNativeTitleBar &&
      previous?.rememberWindowState == current.rememberWindowState;
}
