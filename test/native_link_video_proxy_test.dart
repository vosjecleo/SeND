import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:deltiecord/services/link_preview_service.dart';
import 'package:deltiecord/services/native_link_video_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Transport implements DirectPreviewTransport {
  int requests = 0;
  bool redirectToPrivate = false;
  bool ignoresRanges = false;
  @override
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
    Map<String, String> headers = const {},
  }) async {
    requests++;
    if (redirectToPrivate) {
      return DirectPreviewResponse(
        statusCode: 302,
        body: const Stream.empty(),
        location: Uri.parse('http://127.0.0.1/private'),
      );
    }
    final bytes = [0, 0, 0, 32, ...'ftypisom'.codeUnits, ...List.filled(20, 0)];
    return DirectPreviewResponse(
      statusCode: ignoresRanges ? 200 : 206,
      body: Stream.value(bytes),
      contentType: 'video/mp4',
      contentLength: bytes.length,
      contentRange: ignoresRanges ? null : 'bytes 0-31/32',
    );
  }
}

/// Keep read-ahead streams open just as a decoder can after a seek. There is
/// no public network or large video allocation in these concurrency tests.
class _ReadAheadTransport implements DirectPreviewTransport {
  int active = 0, peak = 0;
  final cancelled = <Completer<void>>[];

  @override
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
    Map<String, String> headers = const {},
  }) async {
    const total = 1048576;
    final range = headers[HttpHeaders.rangeHeader]!;
    if (range == 'bytes=0-31') {
      return DirectPreviewResponse(
        statusCode: 206,
        contentType: 'video/mp4',
        contentLength: 32,
        contentRange: 'bytes 0-31/$total',
        body: Stream.value([
          0,
          0,
          0,
          32,
          ...'ftypisom'.codeUnits,
          ...List.filled(20, 0),
        ]),
      );
    }
    final start = int.parse(range.substring(6).split('-').first);
    final done = Completer<void>();
    cancelled.add(done);
    late StreamController<List<int>> body;
    body = StreamController<List<int>>(
      onListen: () {
        active++;
        peak = math.max(peak, active);
        body.add(List.filled(32, 0));
      },
      onCancel: () {
        active--;
        done.complete();
      },
    );
    return DirectPreviewResponse(
      statusCode: 206,
      contentType: 'video/mp4',
      contentLength: total - start,
      contentRange: 'bytes $start-${total - 1}/$total',
      body: body.stream,
    );
  }
}

void main() {
  test(
    'repeated seeks retire stale read-ahead without exceeding two origins',
    () async {
      final origin = _ReadAheadTransport();
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          resolveHost: (_) async => [InternetAddress('93.184.216.34')],
          transport: origin,
        ),
      );
      addTearDown(proxy.close);
      final local = await proxy.open(Uri.parse('https://video.test/movie'));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final subscriptions = <StreamSubscription<List<int>>>[];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      for (final start in [0, 128, 256, 512, 64]) {
        final request = await client.getUrl(local);
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        expect(response.statusCode, 206);
        expect(
          response.headers.value(HttpHeaders.contentRangeHeader),
          'bytes $start-1048575/1048576',
        );
        // Earlier requests deliberately end short when superseded. The decoder
        // no longer needs them; the newest requested range must still succeed.
        subscriptions.add(response.listen((_) {}, onError: (Object _) {}));
        expect(origin.active, lessThanOrEqualTo(2));
      }
      expect(origin.peak, 2);
      expect(origin.cancelled.where((done) => done.isCompleted).length, 3);
      await proxy.close();
      await Future.wait(
        origin.cancelled.map((done) => done.future),
      ).timeout(const Duration(seconds: 2));
      expect(origin.active, 0);
    },
  );

  test('invalid ranges cannot evict active playback transfers', () async {
    final origin = _ReadAheadTransport();
    final proxy = NativeLinkVideoProxy(
      fetcher: DirectLinkPreviewFetcher(
        resolveHost: (_) async => [InternetAddress('93.184.216.34')],
        transport: origin,
      ),
    );
    addTearDown(proxy.close);
    final local = await proxy.open(Uri.parse('https://video.test/movie'));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final streams = <StreamSubscription<List<int>>>[];
    addTearDown(() async {
      for (final stream in streams) {
        await stream.cancel();
      }
    });
    for (final start in [0, 128]) {
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-');
      final response = await request.close();
      streams.add(response.listen((_) {}, onError: (Object _) {}));
    }
    for (final range in ['bytes=-', 'bytes=-0', 'bytes=5-1', 'bytes=1-2,4-5']) {
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      expect(response.statusCode, 400);
      await response.drain<void>();
    }
    final request = await client.getUrl(local);
    final busy = await request.close();
    expect(busy.statusCode, 503);
    await busy.drain<void>();
    expect(origin.active, 2);
    expect(origin.cancelled.any((done) => done.isCompleted), isFalse);
  });
  test('a non-range origin is not advertised as seekable', () async {
    final proxy = NativeLinkVideoProxy(
      fetcher: DirectLinkPreviewFetcher(
        resolveHost: (_) async => [InternetAddress('93.184.216.34')],
        transport: _Transport()..ignoresRanges = true,
      ),
    );
    addTearDown(proxy.close);
    final local = await proxy.open(Uri.parse('https://video.test/movie'));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(local)).close();
    expect(response.statusCode, 200);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), isNull);
    await response.drain<void>();
    final seek = await client.getUrl(local);
    seek.headers.set(HttpHeaders.rangeHeader, 'bytes=16-31');
    final failed = await seek.close();
    expect(failed.statusCode, 502);
    await failed.drain<void>();
  });
  test(
    'wrong-start seek responses are rejected rather than restarting video',
    () async {
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          resolveHost: (_) async => [InternetAddress('93.184.216.34')],
          transport: _Transport(),
        ),
      );
      addTearDown(proxy.close);
      final local = await proxy.open(Uri.parse('https://video.test/movie'));
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=16-31');
      final response = await request.close();
      expect(response.statusCode, 502);
      await response.drain<void>();
    },
  );
  test(
    'playback re-resolution cannot connect privately after public probe',
    () async {
      var private = false;
      final transport = _Transport();
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          resolveHost: (_) async => [
            InternetAddress(private ? '127.0.0.1' : '93.184.216.34'),
          ],
          transport: transport,
        ),
      );
      addTearDown(proxy.close);
      final local = await proxy.open(Uri.parse('http://video.test/movie'));
      expect(local.host, '127.0.0.1');
      expect(transport.requests, 1);
      private = true;
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final response = await (await http.getUrl(local)).close();
      await response.drain<void>();
      expect(response.statusCode, 502);
      expect(transport.requests, 1); // No connection to a private origin.
    },
  );
  test(
    'changed redirects are checked at playback and token is required',
    () async {
      final transport = _Transport();
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          resolveHost: (host) async => [
            InternetAddress(host == '127.0.0.1' ? host : '93.184.216.34'),
          ],
          transport: transport,
        ),
      );
      addTearDown(proxy.close);
      final local = await proxy.open(Uri.parse('https://video.test/movie'));
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      final denied = await (await http.getUrl(
        local.replace(path: '/media/wrong'),
      )).close();
      await denied.drain<void>();
      expect(denied.statusCode, 404);
      transport.redirectToPrivate = true;
      final response = await (await http.getUrl(local)).close();
      await response.drain<void>();
      expect(response.statusCode, 502);
      expect(transport.requests, 2);
    },
  );
  test('manifests cannot masquerade as a supported video container', () {
    for (final text in [
      '#EXTM3U\nhttp://127.0.0.1/private',
      '<MPD><BaseURL>http://localhost/x</BaseURL></MPD>',
      '[playlist]\nFile1=http://localhost/private',
    ]) {
      expect(NativeLinkVideoProxy.containerFormat(text.codeUnits), isNull);
    }
  });
}
