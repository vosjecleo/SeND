import 'dart:convert';
import 'package:cryptography/cryptography.dart';

// Public verification keys only. Never add private signing material here.
const releaseVerificationKeys = {
  'send-release-2026-10': 'oTTEz9lYblSdm/Fj1cXBrbqTDCGvbcwSxIHLRRTYHgc=',
};
const releaseSignatureDomain = 'SeND release metadata v1\n';

/// Detached signature over the exact UTF-8 bytes, including a domain separator.
/// HTTPS, bounded downloads and installer/package checks remain required too.
Future<DateTime> verifyReleaseSignature(
  String source,
  String signature, {
  Map<String, String> trustedKeys = releaseVerificationKeys,
  DateTime? now,
}) async {
  const invalid = FormatException('Release signature verification failed.');
  try {
    final envelope = jsonDecode(signature);
    if (envelope is! Map || envelope['algorithm'] != 'Ed25519') throw invalid;
    final key = trustedKeys[envelope['key_id']];
    if (key == null) throw invalid;
    final publicBytes = base64Decode(key);
    final signedBytes = base64Decode(envelope['signature'] as String);
    if (publicBytes.length != 32 || signedBytes.length != 64) throw invalid;
    final verified = await Ed25519().verify(
      utf8.encode('$releaseSignatureDomain$source'),
      signature: Signature(
        signedBytes,
        publicKey: SimplePublicKey(publicBytes, type: KeyPairType.ed25519),
      ),
    );
    if (!verified) throw invalid;
    final metadata = jsonDecode(source);
    if (metadata is! Map || metadata['signature_schema'] != 1) throw invalid;
    final issued = DateTime.parse(metadata['signed_at'] as String);
    final expires = DateTime.parse(metadata['expires_at'] as String);
    final clock = now ?? DateTime.now().toUtc();
    if (!issued.isUtc ||
        !expires.isUtc ||
        !expires.isAfter(issued) ||
        expires.difference(issued) > const Duration(days: 90) ||
        issued.isAfter(clock.add(const Duration(minutes: 5))) ||
        !expires.isAfter(clock)) {
      throw const FormatException(
        'Release metadata has expired or its date is invalid.',
      );
    }
    return issued;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw invalid;
  }
}
