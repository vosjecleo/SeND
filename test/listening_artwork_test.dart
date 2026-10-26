import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/listening_artwork.dart';
import 'package:deltiecord/models/user_activity.dart';

class _Headers implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.body);
  final Object body;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(body))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.body);
  final Object body;
  @override
  final headers = _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async => _Response(body);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.requests);
  final List<Uri> requests;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  void close({bool force = false}) {}
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    requests.add(uri);
    return _Request(
      uri.host == 'musicbrainz.org'
          ? {
              'releases': [
                {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'title': 'Album',
                  'artist-credit': [
                    {'name': 'Artist'},
                  ],
                },
              ],
            }
          : {
              'images': [
                {
                  'front': true,
                  'thumbnails': {
                    '500':
                        'http://archive.org/download/mbid-11111111-1111-1111-1111-111111111111/front-500.jpg',
                  },
                },
              ],
            },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'optional cover lookup validates identity, upgrades CAA links and caches results',
    () async {
      final requests = <Uri>[];
      final resolver = ListeningArtwork(clientFactory: () => _Client(requests));
      final art = await resolver.lookup('Artist', 'Album');
      expect(art?.scheme, 'https');
      expect(art?.host, 'archive.org');
      expect(await resolver.lookup('Artist', 'Album'), art);
      expect(requests.length, 2);
      expect(
        requests.first.queryParameters.keys,
        unorderedEquals(['query', 'fmt', 'limit']),
      );
    },
  );
  test(
    'covers reject lookalike hosts, credentials, arbitrary paths and active URLs',
    () {
      for (final uri in [
        'https://archive.org.evil.test/download/mbid-11111111-1111-1111-1111-111111111111/a.jpg',
        'https://archive.org/other.jpg',
        'https://user@archive.org/download/mbid-11111111-1111-1111-1111-111111111111/a.jpg',
        'javascript:alert(1)',
        'https://coverartarchive.org/release/11111111-1111-1111-1111-111111111111/front-500?token=secret',
      ]) {
        expect(validListeningArtwork(uri), isNull);
      }
    },
  );
}
