import 'dart:typed_data';
import 'package:deltiecord/matrix/rtc/rtc_key_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

class _RawProvider implements rtc.KeyProvider {
  var sifCalls = 0;
  @override
  Future<void> setSifTrailer({required Uint8List trailer}) async {
    sifCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('server trailers cannot enable plaintext SIF bypass', () async {
    final raw = _RawProvider();
    final provider = MatrixRtcKeyProvider(
      raw,
      rtc.KeyProviderOptions(
        sharedKey: false,
        ratchetWindowSize: 0,
        failureTolerance: -1,
        ratchetSalt: Uint8List.fromList('LKFrameEncryptionKey'.codeUnits),
        discardFrameWhenCryptorNotReady: true,
        keyRingSize: 256,
        keyDerivationAlgorithm: rtc.KeyDerivationAlgorithm.kHKDF,
      ),
    );
    await provider.setSifTrailer(Uint8List.fromList([1, 2, 3]));
    expect(raw.sifCalls, 0);
    expect(provider.options.uncryptedMagicBytes, isNull);
  });
  test('unsafe provider configuration is rejected', () {
    expect(
      () => MatrixRtcKeyProvider(
        _RawProvider(),
        rtc.KeyProviderOptions(
          sharedKey: true,
          ratchetSalt: Uint8List(1),
          ratchetWindowSize: 0,
          failureTolerance: -1,
        ),
      ),
      throwsArgumentError,
    );
  });
}
