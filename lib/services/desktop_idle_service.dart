import 'package:flutter/services.dart';

/// Reads only session idle duration, never keys, windows or pointer positions.
class DesktopIdleService {
  static const timeout = Duration(minutes: 10);
  static const _channel = MethodChannel('net.deltie.deltiecord/window');

  static Future<Duration?> elapsed() async {
    try {
      final milliseconds = await _channel
          .invokeMethod<int>('idleMilliseconds')
          .timeout(const Duration(seconds: 2));
      return milliseconds == null || milliseconds < 0
          ? null
          : Duration(milliseconds: milliseconds);
    } catch (_) {
      return null;
    }
  }
}
