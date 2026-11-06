// Host smoke test: flutter test tool/native_video_boundary_smoke_test.dart
// Requires ffmpeg and mpv; all media and network responses are synthetic.
import 'dart:io';
import 'dart:typed_data';
import 'package:deltiecord/services/link_preview_service.dart';
import 'package:deltiecord/services/native_link_video_proxy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

Future<File> _videoFixture() async {
  final directory = await Directory.systemTemp.createTemp(
    'send-safe-video-smoke-',
  );
  addTearDown(() => directory.delete(recursive: true));
  final file = File('${directory.path}/fixture.mp4');
  final generated = await Process.run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=c=black:s=64x64:r=5',
    '-t',
    '1',
    '-an',
    '-c:v',
    'libx264',
    '-threads',
    '1',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    file.path,
  ]);
  expect(generated.exitCode, 0);
  return file;
}

class _FileTransport implements DirectPreviewTransport {
  _FileTransport(this.bytes);
  final Uint8List bytes;
  int calls = 0;
  @override
  Future<DirectPreviewResponse> get(
    Uri url,
    InternetAddress address, {
    required String accept,
    Map<String, String> headers = const {},
  }) async {
    calls++;
    final range = RegExp(
      r'bytes=(\d+)-(\d*)',
    ).firstMatch(headers['range'] ?? '');
    final start = range == null ? 0 : int.parse(range.group(1)!);
    final end = range == null || range.group(2)!.isEmpty
        ? bytes.length - 1
        : int.parse(range.group(2)!);
    return DirectPreviewResponse(
      statusCode: range == null ? 200 : 206,
      body: Stream.value(bytes.sublist(start, end + 1)),
      contentType: 'video/mp4',
      contentLength: end - start + 1,
      contentRange: range == null ? null : 'bytes $start-$end/${bytes.length}',
    );
  }
}

void main() {
  test(
    'real MediaKit loads a protected video without its temporary M3U and supports replay',
    () async {
      MediaKit.ensureInitialized();
      final file = await _videoFixture();
      final transport = _FileTransport(await file.readAsBytes());
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          transport: transport,
          resolveHost: (_) async => [InternetAddress('93.184.216.34')],
        ),
      );
      final player = Player();
      addTearDown(player.dispose);
      addTearDown(proxy.close);
      await player.setVolume(0);
      final errors = <String>[];
      final subscription = player.stream.error.listen(errors.add);
      addTearDown(subscription.cancel);
      final ready = player.stream.duration.firstWhere(
        (value) => value > Duration.zero,
      );
      await proxy.openAndPlay(
        player,
        Uri.parse('https://synthetic-video.test/fixture.mp4'),
      );
      await ready.timeout(const Duration(seconds: 10));
      expect(player.state.playlist.medias, hasLength(1));
      expect(
        Uri.parse(player.state.playlist.medias.single.uri).host,
        '127.0.0.1',
      );
      await player.pause();
      expect(player.state.playing, false);
      await player.seek(Duration.zero);
      await player.play();
      expect(player.state.playing, true);
      expect(errors, isEmpty);
      expect(transport.calls, greaterThanOrEqualTo(2));
    },
  );
  test(
    'real mpv decodes an MP4 through the safe proxy with nested protocols disabled',
    () async {
      final file = await _videoFixture();
      final transport = _FileTransport(await file.readAsBytes());
      final proxy = NativeLinkVideoProxy(
        fetcher: DirectLinkPreviewFetcher(
          transport: transport,
          resolveHost: (_) async => [InternetAddress('93.184.216.34')],
        ),
      );
      addTearDown(proxy.close);
      final uri = await proxy.open(
        Uri.parse('https://synthetic-video.test/fixture.mp4'),
      );
      final player = await Process.run('mpv', [
        '--no-config',
        '--vo=null',
        '--ao=null',
        '--frames=1',
        '--access-references=no',
        '--load-unsafe-playlists=no',
        '--demuxer-lavf-format=${proxy.format}',
        '--demuxer-lavf-o=protocol_whitelist=none',
        uri.toString(),
      ]).timeout(const Duration(seconds: 15));
      expect(player.exitCode, 0, reason: '${player.stdout}${player.stderr}');
      expect('${player.stdout}${player.stderr}', contains('VO: [null]'));
      expect(transport.calls, greaterThanOrEqualTo(2));
    },
  );
}
