import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/lastfm_activity.dart';

class Headers implements HttpHeaders {
  Headers(this.policy);
  final String policy;
  @override
  String? value(String name) => name == 'cache-control' ? policy : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(this.policy, this.statusCode);
  final String policy;
  @override
  final int statusCode;
  @override
  HttpHeaders get headers => Headers(policy);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(
        utf8.encode(
          jsonEncode({
            'recenttracks': {
              'track': [
                {
                  'name': 'Playing',
                  'artist': {'#text': 'Artist'},
                  '@attr': {'nowplaying': 'true'},
                },
                {
                  'name': 'Completed',
                  'artist': {'#text': 'Artist'},
                  'album': {'#text': 'Album'},
                  'date': {'uts': '1700000000'},
                },
              ],
            },
          }),
        ),
      ).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Request implements HttpClientRequest {
  Request(this.response);
  final Response response;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Client implements HttpClient {
  Client(this.response, this.onRead);
  final Response response;
  final void Function() onRead;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    onRead();
    return Request(response);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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
