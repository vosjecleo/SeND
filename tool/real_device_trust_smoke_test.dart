// Run after a native build. SEND_NATIVE_CRYPTO_LIBRARY can select another
// directory containing the matching vodozemac library. No live accounts used.
import 'dart:io';
import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_membership_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

class _DB extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends RtcMatrixClient {
  _Client() : super('synthetic-trust-smoke', database: _DB());
  @override
  bool get encryptionEnabled => true;
}

void main() {
  test('actual Ed25519 chain gates both message and RTC recipients', () async {
    await vod.init(
      libraryPath:
          Platform.environment['SEND_NATIVE_CRYPTO_LIBRARY'] ??
          'build/linux/x64/release/bundle/lib/',
    );
    final client = _Client();
    addTearDown(client.dispose);
    const user = '@synthetic:test';
    final list = client.userDeviceKeys[user] = DeviceKeysList(user, client);
    final masterSigner = vod.PkSigning(),
        selfSigner = vod.PkSigning(),
        deviceSigner = vod.PkSigning();
    final masterPublic = masterSigner.publicKey.toBase64(),
        selfPublic = selfSigner.publicKey.toBase64();
    final device = DeviceKeys.fromJson({
      'user_id': user,
      'device_id': 'NEW',
      'algorithms': <String>[],
      'keys': {
        'ed25519:NEW': deviceSigner.publicKey.toBase64(),
        'curve25519:NEW': 'synthetic-curve',
      },
    }, client);
    device.signatures = {
      user: {
        'ed25519:NEW': deviceSigner.sign(device.signingContent).toBase64(),
      },
    };
    list.deviceKeys['NEW'] = device;
    expect(device.selfSigned, true);
    expect(device.encryptToDevice, true);
    final master = CrossSigningKey.fromJson({
      'user_id': user,
      'usage': ['master'],
      'keys': {'ed25519:$masterPublic': masterPublic},
    }, client);
    list.crossSigningKeys[masterPublic] = master;
    final room = Room(
      id: '!call:test',
      client: client,
      membership: Membership.join,
    );
    final member = RtcMember(
      userId: user,
      deviceId: 'NEW',
      memberId: 'member',
      createdAt: DateTime(2026),
      expiresAt: DateTime(2030),
      transports: const [],
    );
    expect(device.encryptToDevice, false);
    expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
    final selfKey = CrossSigningKey.fromJson({
      'user_id': user,
      'usage': ['self_signing'],
      'keys': {'ed25519:$selfPublic': selfPublic},
    }, client);
    selfKey.signatures = {
      user: {
        'ed25519:$masterPublic': masterSigner
            .sign(selfKey.signingContent)
            .toBase64(),
      },
    };
    list.crossSigningKeys[selfPublic] = selfKey;
    device.signatures![user]!['ed25519:$selfPublic'] = selfSigner
        .sign(device.signingContent)
        .toBase64();
    expect(device.encryptToDevice, true);
    expect(rtcMediaKeyRecipients(room, [member]), [device]);
    device.blocked = true;
    expect(device.encryptToDevice, false);
    expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
    device.blocked = false;
    device.validSignatures = null;
    device.signatures![user]!['ed25519:$selfPublic'] = masterSigner
        .sign(device.signingContent)
        .toBase64();
    expect(device.encryptToDevice, false);
    expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
  });
}
