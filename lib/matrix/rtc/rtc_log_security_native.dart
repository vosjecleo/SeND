import 'dart:ffi';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

Future<void>? _ready;
Future<void> silenceRtcDebugLogging() => _ready ??= _silence();

Future<void> _silence() async {
  await rtc.WebRTC.initialize(options: {'logSeverity': 'none'});
  if (Platform.isAndroid) {
    await const MethodChannel('net.deltie.send/rtc_security')
        .invokeMethod<void>('silenceDebugLogging')
        .timeout(const Duration(seconds: 5));
    return;
  }
  if (Platform.isLinux || Platform.isWindows) {
    // Pinned libwebrtc m150 exports this public C++ SDK method. Its only
    // argument is RTCLoggingSeverity (a 32-bit enum, None = 4); no C++ objects
    // cross the ABI. setLogSink alone does NOT disable stderr key logging.
    final library = DynamicLibrary.open(
      Platform.isWindows ? 'libwebrtc.dll' : 'libwebrtc.so',
    );
    final symbol = Platform.isWindows
        ? '?setMinDebugLogLevel@LibWebRTCLogging@libwebrtc@@SAXW4RTCLoggingSeverity@2@@Z'
        : '_ZN9libwebrtc16LibWebRTCLogging19setMinDebugLogLevelENS_18RTCLoggingSeverityE';
    final silence = library
        .lookupFunction<Void Function(Int32), void Function(int)>(symbol);
    silence(4);
    return;
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // Objective-C WebRTC exposes the same global debug-logging control.
    final silence = DynamicLibrary.process()
        .lookupFunction<Void Function(Int32), void Function(int)>(
          'RTCSetMinDebugLogLevel',
        );
    silence(4);
  }
}
