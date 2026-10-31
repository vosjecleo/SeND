import 'support/lastfm_http_fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/lastfm_activity.dart';

void main() {
  test(
    'now-playing selects largest supplied trusted artwork; survives profile roundtrip',
    () {
      const art = 'https://lastfm.freetls.fastly.net/i/u/300x300/cover.png';
      final candidate = lastFmNowPlaying({
        'recenttracks': {
          'track': [
            {
              'name': 'Song',
              '@attr': {'nowplaying': 'true'},
              'image': [
                {
                  'size': 'small',
                  '#text':
                      'https://lastfm.freetls.fastly.net/i/u/34s/cover.png',
                },
                {'size': 'extralarge', '#text': art},
                {'size': 'mega', '#text': 'https://untrusted.example/track'},
              ],
            },
          ],
        },
      }, 'user');
      expect(candidate?.lastFmArtwork.toString(), art);
      final record = UserActivity(
        kind: ActivityKind.music,
        name: 'Song',
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        lastFmUrl: candidate!.lastFmUrl,
        lastFmArtwork: candidate.lastFmArtwork,
      );
      expect(
        UserActivity.fromJson(record.toJson())?.lastFmArtwork.toString(),
        art,
      );
      expect(
        validLastFmArtwork(
          'https://lastfm.freetls.fastly.net.attacker.test/i/u/cover.png',
        ),
        isNull,
      );
      expect(validLastFmArtwork('file:///cover.png'), isNull);
    },
  );
  const settings = ActivitySettings(
    lastFmUser: 'user',
    lastFmKey: 'fake-key',
    share: true,
    showLastFmRecent: true,
  );
  for (final policy in ['max-age=60', 'no-store']) {
    test('resume restores music/footer respecting $policy', () async {
      var now = DateTime.now();
      var reads = 0;
      final source = LastFmActivitySource(
        now: () => now,
        clientFactory: () => Client(Response(policy, 200), () => reads++),
      );
      expect((await source.scan(settings))?.name, 'Playing');
      expect(source.recent?.name, 'Completed');
      source.suspend();
      now = now.add(const Duration(seconds: 5));
      expect((await source.scan(settings))?.name, 'Playing');
      expect(source.recent?.name, 'Completed');
      expect(reads, policy == 'no-store' ? 2 : 1);
      now = now.add(const Duration(minutes: 2));
      source.suspend();
      expect((await source.scan(settings))?.name, 'Playing');
      expect(reads, policy == 'no-store' ? 3 : 2);
    });
  }
  test('resume does not reset server rate-limit cooldown', () async {
    var now = DateTime.now();
    var reads = 0;
    final source = LastFmActivitySource(
      now: () => now,
      clientFactory: () => Client(Response('', 429), () => reads++),
    );
    await source.scan(settings);
    source.suspend();
    now = now.add(const Duration(seconds: 5));
    await source.scan(settings);
    expect(reads, 1);
    expect(source.recent, isNull);
  });
}
