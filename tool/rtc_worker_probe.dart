import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import '../third_party/livekit_e2ee/e2ee.keyhandler.dart';

/// Browser-only public-vector test fixture, never shipped as the RTC worker.
void main() {
  final self = globalContext as web.DedicatedWorkerGlobalScope;
  self.onmessage = ((web.MessageEvent event) {
    final data = event.data.dartify() as Map;
    Future<void>(() async {
      try {
        final options = KeyOptions(
          sharedKey: false,
          ratchetSalt: Uint8List.fromList(utf8.encode('LKFrameEncryptionKey')),
          ratchetWindowSize: 0,
          keyRingSze: 256,
          keyDerivationAlgorithm: data['algorithm'] as int,
        );
        final handler = ParticipantKeyHandler(
          worker: self,
          participantIdentity: 'public-test-vector',
          keyOptions: options,
        );
        await handler.setKey(
          Uint8List.fromList(List.generate(32, (i) => i)),
          keyIndex: 255,
        );
        final key = handler.getKeySet(255)!;
        final cipher = await self.crypto.subtle
            .encrypt(
              {'name': 'AES-GCM', 'iv': Uint8List(12).toJS}.jsify()
                  as web.AlgorithmIdentifier,
              key.encryptionKey,
              Uint8List.fromList(
                utf8.encode('MatrixRTC interoperability'),
              ).toJS,
            )
            .toDart;
        self.postMessage(
          {
            'index': handler.currentKeyIndex,
            'algorithm': options.algorithmName,
            'cipher': (cipher as JSArrayBuffer).toDart
                .asUint8List()
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          }.jsify(),
        );
      } catch (_) {
        self.postMessage({'error': 'Worker cryptography probe failed'}.jsify());
      }
    });
  }).toJS;
}
