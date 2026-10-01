import 'package:deltiecord/models/rtc_connectivity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only successful selected media candidate pairs contribute RTT', () {
    expect(
      rtcPingMilliseconds([
        {
          'state': 'succeeded',
          'nominated': true,
          'currentRoundTripTime': 0.042,
        },
        {'state': 'succeeded', 'selected': true, 'currentRoundTripTime': 0.12},
        {'state': 'failed', 'nominated': true, 'currentRoundTripTime': 9},
        {'state': 'succeeded', 'currentRoundTripTime': 8},
        {
          'state': 'succeeded',
          'nominated': true,
          'currentRoundTripTime': double.nan,
        },
      ]),
      120,
    );
    expect(rtcPingMilliseconds([]), isNull);
  });
  test('waiting does not invent a zero-millisecond ping', () {
    expect(const RtcConnectivity().description, contains('unavailable'));
    expect(const RtcConnectivity().state, RtcConnectivityState.waiting);
  });
}
