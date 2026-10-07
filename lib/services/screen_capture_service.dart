import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenCaptureService {
  static const _channel = MethodChannel('net.deltie.deltiecord/screen_share');
  static bool _started = false;
  static bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> prepare({
    Future<bool> Function()? requestPermission,
  }) async {
    if (!_android) return true;
    // Request a fresh, single-use projection token for each capture session.
    if (!await (requestPermission ?? Helper.requestCapturePermission)()) {
      return false;
    }
    _started = true;
    await _channel.invokeMethod<void>('start');
    return true;
  }

  static Future<void> stop() async {
    if (!_android || !_started) return;
    _started = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Do not prevent RTC cleanup if Android has already stopped the service.
    } on MissingPluginException {
      // Headless/test engines do not own screen capture.
    }
  }
}
