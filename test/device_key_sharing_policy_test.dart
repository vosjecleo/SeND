import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:deltiecord/matrix/rtc/rtc_membership_session.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  @override
  Future<void> close() async {}
}

class _Client extends RtcMatrixClient {
  _Client() : super('trust-policy-test', database: _Database());
  @override
  bool get encryptionEnabled => true;
}

// This suite tests recipient policy, not the SDK's signature primitive. Model
// an already self-validated device while exercising the real trust-chain walk.
class _SelfSignedDevice extends DeviceKeys {
  _SelfSignedDevice(super.json, super.client) : super.fromJson();
  @override
  bool get selfSigned => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'messages and RTC exclude unsigned devices once cross-signing is enabled',
    () async {
      final client = _Client();
      addTearDown(client.dispose);
      expect(client.shareKeysWith, ShareKeysWith.crossVerifiedIfEnabled);
      const user = '@friend:test';
      final room = Room(
        id: '!call:test',
        client: client,
        membership: Membership.join,
      );
      final list = client.userDeviceKeys[user] = DeviceKeysList(user, client);
      final device = _SelfSignedDevice({
        'user_id': user,
        'device_id': 'NEW',
        'algorithms': <String>[],
        'keys': {
          'ed25519:NEW': 'device-public-key',
          'curve25519:NEW': 'curve-public-key',
        },
      }, client);
      device.signatures = {
        user: {'ed25519:NEW': 'validated-device-signature'},
      };
      device.validSignatures = {
        user: {'ed25519:NEW': true},
      };
      list.deviceKeys['NEW'] = device;
      final member = RtcMember(
        userId: user,
        deviceId: 'NEW',
        memberId: 'member',
        createdAt: DateTime(2026),
        expiresAt: DateTime(2030),
        transports: const [],
      );
      // No master key: preserve SDK interoperability with non-cross-signing clients.
      expect(device.encryptToDevice, true);
      expect(rtcMediaKeyRecipients(room, [member]), [device]);
      final master = CrossSigningKey.fromJson({
        'user_id': user,
        'usage': ['master'],
        'keys': {'ed25519:master': 'master'},
      }, client);
      list.crossSigningKeys['master'] = master;
      expect(device.encryptToDevice, false);
      expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
      // Persisted signature-validation results follow the SDK's same chain walk
      // used for outbound Megolm. This test does not mock encryptToDevice.
      device.signatures = {
        user: {
          'ed25519:NEW': 'validated-device-signature',
          'ed25519:master': 'validated-signature',
        },
      };
      device.validSignatures = {
        user: {'ed25519:NEW': true, 'ed25519:master': true},
      };
      expect(device.encryptToDevice, true);
      expect(rtcMediaKeyRecipients(room, [member]), [device]);
      device.blocked = true;
      expect(device.encryptToDevice, false);
      expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
      device.blocked = false;
      device.validSignatures = {
        user: {'ed25519:NEW': true, 'ed25519:master': false},
      };
      expect(device.encryptToDevice, false);
      expect(rtcMediaKeyRecipients(room, [member]), isEmpty);
    },
  );
}
