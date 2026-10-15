import 'package:matrix/matrix.dart';

/// Remove only abandoned devices created by this RTC probe, never ordinary
/// SeND sessions. Current test devices are logged out by the probe's finally.
Future<int> removeAbandonedRtcProbeDevices(
  Client client,
  String password,
) async {
  final devices = (await client.getDevices() ?? [])
      .where(
        (device) =>
            device.deviceId != client.deviceID &&
            [
              'SeND RTC temporary test',
              'SeND RTC temporary browser test',
            ].contains(device.displayName),
      )
      .map((device) => device.deviceId)
      .toList();
  if (devices.isEmpty) return 0;
  try {
    await client.deleteDevices(devices);
  } on MatrixException catch (error) {
    if (!error.requireAdditionalAuthentication) rethrow;
    await client.deleteDevices(
      devices,
      auth: AuthenticationPassword(
        identifier: AuthenticationUserIdentifier(user: client.userID!),
        password: password,
        session: error.session,
      ),
    );
  }
  return devices.length;
}
