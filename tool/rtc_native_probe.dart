import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:deltiecord/matrix/rtc/rtc_log_security.dart';

/// No account, network, microphone or camera is used. Run with:
/// flutter run -d linux -t tool/rtc_native_probe.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await silenceRtcDebugLogging();
    final options = rtc.KeyProviderOptions(
      sharedKey: false,
      ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
      ratchetWindowSize: 0,
      keyRingSize: 256,
      discardFrameWhenCryptorNotReady: true,
      keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
    );
    final provider = await rtc.frameCryptorFactory.createDefaultKeyProvider(
      options,
    );
    final accepted = await provider.setKey(
      participantId: 'public-test-vector',
      index: 255,
      key: Uint8List.fromList(List.generate(32, (i) => i)),
    );
    final exported = await provider.exportKey(
      participantId: 'public-test-vector',
      index: 255,
    );
    await provider.dispose();
    if (!accepted || exported.length != 32) {
      throw StateError('Key-ring probe failed');
    }
    debugPrint('RTC_NATIVE_PROBE_OK: HKDF provider, 256 entries, index 255');
    exit(0);
  } catch (error) {
    debugPrint('RTC_NATIVE_PROBE_FAILED: $error');
    exit(1);
  }
}
