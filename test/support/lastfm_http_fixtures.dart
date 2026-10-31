import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
