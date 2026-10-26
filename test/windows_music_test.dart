import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/windows_music.dart';

void main() {
  test(
    'Spotify desktop and Store IDs are music, even with default RPC type',
    () {
      for (final id in [
        r'C:\Users\name\AppData\Roaming\Spotify\Spotify.exe',
        'SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify',
      ]) {
        expect(isSpotifyApplication(id), true);
        expect(richPresenceKind(0, id), ActivityKind.music);
      }
      expect(richPresenceKind(0, 'C:/Games/game.exe'), ActivityKind.game);
      expect(isSpotifyApplication('NotSpotify.exe'), false);
    },
  );
  test('Windows media session provides track, artist and bounded progress', () {
    final now = DateTime.utc(2026, 10, 26);
    final row = {
      'source': 'Spotify.exe',
      'title': 'Song',
      'artist': 'Artist',
      'state': 'Playing',
      'position': 42000,
      'duration': 180000,
    };
    final music = windowsMusicFromJson(row, now: now)!;
    expect(music.name, 'Song');
    expect(music.details, 'Artist');
    expect(music.kind, ActivityKind.music);
    expect(music.playback!.positionMs, 42000);
    expect(music.playback!.durationMs, 180000);
    expect(music.playback!.playing, true);
    expect(
      windowsMusicFromJson({
        ...row,
        'state': 'Paused',
      }, now: now)!.playback!.playing,
      false,
    );
    expect(windowsMusicFromJson({...row, 'state': 'Stopped'}), isNull);
    expect(windowsMusicFromJson({...row, 'title': ''}), isNull);
    expect(
      windowsMusicFromJson({...row, 'source': 'browser.exe', 'type': 'Video'}),
      isNull,
    );
    expect(
      windowsMusicFromJson({...row, 'source': 'player.exe', 'type': 'Music'}),
      isNotNull,
    );
  });
}
