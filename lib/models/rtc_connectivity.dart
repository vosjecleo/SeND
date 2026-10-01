enum RtcConnectivityState { unavailable, waiting, connected }

class RtcConnectivity {
  const RtcConnectivity({
    this.state = RtcConnectivityState.waiting,
    this.connectedPeers = 0,
    this.totalPeers = 0,
    this.pingMilliseconds,
    this.detail = 'Waiting for an RTC connection',
  });

  final RtcConnectivityState state;
  final int connectedPeers;
  final int totalPeers;
  final int? pingMilliseconds;
  final String detail;

  String get description =>
      '$detail\n${pingMilliseconds == null ? 'RTC ping unavailable' : 'RTC ping: $pingMilliseconds ms (slowest peer)'}';
}

/// Only a nominated/selected successful candidate pair measures media-path RTT.
int? rtcPingMilliseconds(Iterable<Map<String, dynamic>> candidatePairs) {
  int? result;
  for (final pair in candidatePairs) {
    if (pair['state'] != 'succeeded' ||
        (pair['nominated'] != true && pair['selected'] != true)) {
      continue;
    }
    final seconds = pair['currentRoundTripTime'];
    if (seconds is! num || !seconds.isFinite || seconds < 0) continue;
    final milliseconds = (seconds * 1000).round();
    if (result == null || milliseconds > result) result = milliseconds;
  }
  return result;
}
