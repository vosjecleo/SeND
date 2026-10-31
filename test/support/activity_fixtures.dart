import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_source.dart';
import 'package:deltiecord/services/lastfm_activity.dart';
import 'fake_backend.dart';

class Source extends DesktopActivitySource {
  List<ActivityCandidate> values = [];
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async =>
      values;
  @override
  Future<void> dispose() async {}
}

final recentTrack = LastFmTrack(
  name: 'Completed song',
  artist: 'Artist',
  album: 'Album',
  url: Uri.parse('https://www.last.fm/music/Artist/_/Song'),
  playedAt: DateTime.now().subtract(const Duration(minutes: 5)),
);

class Feed extends LastFmActivitySource {
  @override
  Future<ActivityCandidate?> scan(ActivitySettings settings) async {
    recent = recentTrack;
    return null;
  }
}

class MultiBackend extends FakeBackend {
  @override
  List<UserActivity> activitiesFor(String id) => [
    for (final kind in [ActivityKind.game, ActivityKind.music])
      UserActivity(
        kind: kind,
        name: kind.name,
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      ),
  ];
  @override
  LastFmTrack? lastFmRecentFor(String id) => recentTrack;
}
