import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:deltiecord/services/release_signatures.dart';
import 'package:deltiecord/services/release_replay_guard.dart';
import 'package:deltiecord/services/update_checker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 29);
  test('Dart verifies the exact OpenSSL publisher wire format', () async {
    // Untrusted fixture key, never a release signer. Generated with pkeyutl.
    const source =
        '{"signature_schema":1,"version":"0.9.42","build":135,"signed_at":"2026-10-29T00:00:00Z","expires_at":"2027-01-27T00:00:00Z"}\n';
    final envelope = jsonEncode({
      'algorithm': 'Ed25519',
      'key_id': 'openssl-fixture',
      'signature':
          'Wf/TavXgPT1/Uk+ca0QIaCYX+77ENvyz0+7z5xsN75BK97BQ41xmg+XmCvzMyp35csDpODuFp83VCpRmfVGBCQ==',
    });
    expect(
      await verifyReleaseSignature(
        source,
        envelope,
        now: now,
        trustedKeys: {
          'openssl-fixture': '8QgaWs2LdDq4tS6isHRZ1imo9/Ohy5bRnkX4f0aAd4Y=',
        },
      ),
      now,
    );
    await expectLater(
      verifyReleaseSignature(source, envelope, now: now),
      throwsFormatException,
    );
  });
  late SimpleKeyPair key;
  late Map<String, String> trust;
  setUp(() async {
    key = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 7));
    trust = {'fixture': base64Encode((await key.extractPublicKey()).bytes)};
  });
  String metadata({DateTime? issued, DateTime? expires, int build = 135}) =>
      jsonEncode({
        'signature_schema': 1,
        'version': '0.9.42',
        'build': build,
        'signed_at': (issued ?? now).toIso8601String(),
        'expires_at': (expires ?? now.add(const Duration(days: 90)))
            .toIso8601String(),
      });
  Future<String> signature(String source) async => jsonEncode({
    'algorithm': 'Ed25519',
    'key_id': 'fixture',
    'signature': base64Encode(
      (await Ed25519().sign(
        utf8.encode('$releaseSignatureDomain$source'),
        keyPair: key,
      )).bytes,
    ),
  });

  test(
    'accepts exact signed bytes, rejects tampering and untrusted keys',
    () async {
      final source = metadata(), signed = await signature(metadata());
      expect(
        await verifyReleaseSignature(
          source,
          signed,
          trustedKeys: trust,
          now: now,
        ),
        now,
      );
      for (final changed in ['$source ', source.replaceFirst('135', '136')]) {
        await expectLater(
          verifyReleaseSignature(changed, signed, trustedKeys: trust, now: now),
          throwsFormatException,
        );
      }
      await expectLater(
        verifyReleaseSignature(source, signed, now: now),
        throwsFormatException,
      );
      await expectLater(
        verifyReleaseSignature(source, '{}', trustedKeys: trust, now: now),
        throwsFormatException,
      );
    },
  );
  test('expiry, future issuance and excessive validity are rejected', () async {
    for (final source in [
      metadata(expires: now),
      metadata(issued: now.add(const Duration(hours: 1))),
      metadata(expires: now.add(const Duration(days: 91))),
    ]) {
      await expectLater(
        verifyReleaseSignature(
          source,
          await signature(source),
          trustedKeys: trust,
          now: now,
        ),
        throwsFormatException,
      );
    }
  });
  test('signed older versions/builds never offer a downgrade', () async {
    final source = metadata(build: 134);
    await verifyReleaseSignature(
      source,
      await signature(source),
      trustedKeys: trust,
      now: now,
    );
    expect(
      parseReleaseManifest(
        source,
        currentVersion: '0.9.42',
        currentBuild: 135,
      ).updateAvailable,
      false,
    );
    expect(
      parseReleaseManifest(
        source,
        currentVersion: '0.9.43',
        currentBuild: 1,
      ).updateAvailable,
      false,
    );
  });
  test('monotonic release state survives reopen and rejects replay', () async {
    FlutterSecureStorage.setMockInitialValues({});
    await ReleaseReplayGuard().accept(now);
    await expectLater(
      ReleaseReplayGuard().accept(now.subtract(const Duration(seconds: 1))),
      throwsFormatException,
    );
    await ReleaseReplayGuard().accept(now);
    await ReleaseReplayGuard().accept(now.add(const Duration(seconds: 1)));
    await expectLater(ReleaseReplayGuard().accept(now), throwsFormatException);
  });
  test(
    'rotation accepts overlapping trusted keys, revoked keys are rejected',
    () async {
      final next = await Ed25519().newKeyPairFromSeed(List<int>.filled(32, 8));
      final overlap = {
        ...trust,
        'next': base64Encode((await next.extractPublicKey()).bytes),
      };
      final source = metadata(), oldSignature = await signature(metadata());
      expect(
        await verifyReleaseSignature(
          source,
          oldSignature,
          trustedKeys: overlap,
          now: now,
        ),
        now,
      );
      overlap.remove('fixture');
      await expectLater(
        verifyReleaseSignature(
          source,
          oldSignature,
          trustedKeys: overlap,
          now: now,
        ),
        throwsFormatException,
      );
    },
  );
}
