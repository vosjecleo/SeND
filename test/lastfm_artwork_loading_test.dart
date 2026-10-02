import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

final _artwork = Uri.parse('https://lastfm-img.freetls.fastly.net/cover.png');

class _Backend extends FakeBackend {
  @override
  List<UserActivity> activitiesFor(String userId) => [
    UserActivity(
      kind: ActivityKind.music,
      name: 'Song',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      lastFmArtwork: _artwork,
    ),
  ];
  @override
  LastFmTrack? lastFmRecentFor(String userId) => LastFmTrack(
    name: 'Previous song',
    artist: 'Artist',
    album: 'Album',
    url: Uri.parse('https://www.last.fm/music/Artist'),
    artwork: _artwork,
    playedAt: DateTime.now(),
  );
}

void main() {
  testWidgets(
    'live and recent Last.fm artwork use COEP-compatible CORS fetch',
    (tester) async {
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: [DeltiecordPalette.forMode(DeltiecordThemeMode.dark)],
          ),
          home: ActivityScope(
            backend: backend,
            child: const Scaffold(
              body: Column(
                children: [
                  ActivityBlock(userId: '@peer:test'),
                  LastFmRecentBar(userId: '@peer:test'),
                ],
              ),
            ),
          ),
        ),
      );
      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(2));
      for (final image in images) {
        final provider = image.image as NetworkImage;
        expect(provider.url, _artwork.toString());
        expect(provider.webHtmlElementStrategy, WebHtmlElementStrategy.never);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
}
