import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// MatrixRTC never accepts LiveKit's plaintext server-injected frames (SIF).
/// The SFU must not enable that bypass by supplying a trailer at connection.
class MatrixRtcKeyProvider extends lk.BaseKeyProvider {
  MatrixRtcKeyProvider(super.provider, super.options) {
    if (options.sharedKey ||
        options.uncryptedMagicBytes != null ||
        !options.discardFrameWhenCryptorNotReady ||
        options.keyDerivationAlgorithm != rtc.KeyDerivationAlgorithm.kHKDF) {
      throw ArgumentError(
        'MatrixRTC requires per-device, fail-closed HKDF keys',
      );
    }
  }

  @override
  Future<void> setSifTrailer(Uint8List trailer) async {
    // Keep the native/worker plaintext exemption unset, including on reconnect.
  }
}
