import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_discovery.dart';
import 'package:deltiecord/services/activity_artwork_native.dart';
import 'package:deltiecord/services/activity_ipc_native.dart';
import 'package:deltiecord/services/activity_source_native.dart';
import 'package:deltiecord/services/lastfm_auth.dart';

void main() {
  test(
    'repeated worker scans work while this source owns a live IPC socket',
    () async {
      final runtime = Platform.environment['XDG_RUNTIME_DIR'];
      if (runtime == null || !runtime.startsWith('/run/user/')) return;
      final directory = await Directory(
        runtime,
      ).createTemp('deltiecord-rpc-regression-');
      final source = DesktopActivitySource(ipcDirectory: directory.path);
      try {
        const settings = ActivitySettings(detect: true, rpc: true);
        await source.scan(settings);
        expect(source.warning, isNull);
        expect(
          await FileSystemEntity.type('${directory.path}/discord-ipc-0'),
          FileSystemEntityType.unixDomainSock,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await source.scan(settings);
        expect(source.warning, isNull);
      } finally {
        await source.dispose();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux,
  );

  test('MPRIS progress uses microseconds and never invents missing timing', () {
    final at = DateTime.now();
    final playback = playbackFromMpris(
      '42000000',
      '239830000',
      'Playing',
      now: at,
    )!;
    expect(playback.positionMs, 42000);
    expect(playback.durationMs, 239830);
    expect(playback.positionAt(at.add(const Duration(seconds: 3))), 45000);
    expect(playbackFromMpris('', '239830000', 'Playing'), isNull);
    expect(playbackFromMpris('0', '1', 'Playing'), isNull);
    final paused = playbackFromMpris(
      '42000000',
      '239830000',
      'Paused',
      now: at,
    )!;
    expect(paused.positionAt(at.add(const Duration(minutes: 1))), 42000);
  });
  test('player metadata enriches music RPC without displacing game RPC', () {
    const music = ActivityCandidate(
      id: 'music:player',
      name: 'Track',
      kind: ActivityKind.music,
    );
    const rpcMusic = ActivityCandidate(
      id: 'rpc',
      name: 'Player',
      kind: ActivityKind.music,
    );
    const rpcGame = ActivityCandidate(
      id: 'game',
      name: 'Game',
      kind: ActivityKind.game,
    );
    expect(preferPlayerMusic(rpcMusic, music), isTrue);
    expect(preferPlayerMusic(rpcGame, music), isFalse);
    expect(preferPlayerMusic(rpcMusic, null), isFalse);
  });
  test('Steam shortcut identity does not mean that Steam is the game', () {
    expect(steamShortcutAppId('steam steam://rungameid/240'), '240');
    expect(
      steamShortcutAppId('"/usr/bin/steam" steam://rungameid/413150'),
      '413150',
    );
    expect(steamShortcutAppId('steam'), isNull);
    const catalogue = [
      ActivityCandidate(
        id: '/games/Stardew Valley/',
        name: 'Stardew Valley',
        kind: ActivityKind.game,
      ),
      ActivityCandidate(
        id: '/games/Counter-Strike Source/',
        name: 'Counter-Strike: Source',
        kind: ActivityKind.game,
      ),
      ActivityCandidate(id: 'steam', name: 'Steam'),
    ];
    expect(matchRunningActivity('/usr/bin/steam', catalogue)!.name, 'Steam');
    expect(
      matchRunningActivity(
        '/games/Stardew Valley/StardewValley',
        catalogue,
      )!.kind,
      ActivityKind.game,
    );
    expect(
      matchRunningActivity(
        '/games/Counter-Strike Source/hl2_linux',
        catalogue,
      )!.name,
      'Counter-Strike: Source',
    );
    expect(
      matchRunningActivity('/games/Stardew Valley Other/game', catalogue),
      isNull,
    );
  });

  test(
    'artwork is bounded, normalized and refreshed when the local file changes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'deltiecord-artwork-test-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final cover = File('${dir.path}/cover.jpg');
      await cover.writeAsBytes(
        img.encodeJpg(img.Image(width: 800, height: 600)),
      );
      final cache = ActivityArtworkCache();
      final first = await cache.load(cover.uri.toString());
      expect(first, isNotNull);
      final decoded = img.decodePng(first!)!;
      expect(decoded.width, 384);
      expect(decoded.height, lessThanOrEqualTo(384));
      expect(identical(await cache.load(cover.uri.toString()), first), isTrue);
      await cover.writeAsBytes(
        img.encodePng(
          img.Image(width: 16, height: 16)
            ..clear(img.ColorRgba8(255, 0, 0, 255)),
        ),
      );
      expect(await cache.load(cover.uri.toString()), isNot(equals(first)));
      expect(
        normalizeActivityArtwork(
          Uint8List.fromList(utf8.encode('not an image')),
        ),
        isNull,
      );
      expect(
        normalizeActivityArtwork(
          Uint8List.fromList(img.encodePng(img.Image(width: 2049, height: 1))),
        ),
        isNull,
      );
      expect(await cache.load('http://127.0.0.1/private'), isNull);
      expect(await cache.load('https://127.0.0.1/private'), isNull);
    },
  );

  test(
    'IPC keeps active listeners and regular files, recovers stale sockets',
    () async {
      final dir = await Directory.systemTemp.createTemp('deltiecord-ipc-test-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/discord-ipc-0';
      await File(path).writeAsString('not a socket');
      expect(await prepareActivitySocket(path, dir.path), isFalse);
      expect(await File(path).readAsString(), 'not a socket');
      await File(path).delete();
      final server = await ServerSocket.bind(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      );
      final sub = server.listen((s) => s.destroy());
      expect(await prepareActivitySocket(path, dir.path), isFalse);
      await sub.cancel();
      await server.close();
      expect(await prepareActivitySocket(path, dir.path), isTrue);
      expect(await FileSystemEntity.type(path), FileSystemEntityType.notFound);
    },
    skip: !Platform.isLinux,
  );

  test(
    'Last.fm browser link signs requests and takes identity from Last.fm',
    () async {
      final token = 'zQ7-' * 8; // Last.fm tokens are opaque, not hex digests.
      final requests = <Map<String, String>>[];
      final auth = LastFmAuth(
        apiKey: 'app-key',
        secret: 'app-secret',
        transport: (params) async {
          requests.add(params);
          return params['method'] == 'auth.getToken'
              ? {'token': token}
              : {
                  'session': {
                    'name': 'verified-name',
                    'key': 'unused-write-session',
                  },
                };
        },
      );
      expect(await auth.begin(), token);
      expect(auth.authorizationUrl(token).host, 'www.last.fm');
      expect(auth.authorizationUrl(token).queryParameters['token'], token);
      expect(await auth.finish(token), 'verified-name');
      expect(
        requests.first['api_sig'],
        md5
            .convert(utf8.encode('api_keyapp-keymethodauth.getTokenapp-secret'))
            .toString(),
      );
      final denied = LastFmAuth(
        apiKey: 'app-key',
        secret: 'secret',
        transport: (_) async => {'error': 14},
      );
      await expectLater(denied.finish(token), throwsA(isA<LastFmAuthError>()));
    },
  );

  test(
    'host smoke: current MPRIS WebP artwork and process identities',
    () async {
      final result = await Process.run('playerctl', [
        '--all-players',
        'metadata',
        '--format',
        '{{mpris:artUrl}}',
      ]);
      final url =
          Platform.environment['DELTIECORD_ARTWORK_SMOKE_URI'] ??
          result.stdout.toString().trim().split('\n').first;
      expect(url.startsWith('file:'), isTrue);
      expect(await ActivityArtworkCache().load(url), isNotNull);
      final catalogue = loadLocalActivityCatalogue();
      for (final name in ['Stardew Valley', 'Counter-Strike: Source']) {
        final item = catalogue.firstWhere((e) => e.name == name);
        expect(item.id.endsWith('/'), isTrue);
        expect(item.kind, ActivityKind.game);
        expect(item.iconBytes, isNotNull);
      }
      final source = DesktopActivitySource();
      addTearDown(source.dispose);
      final activities = await source.scan(
        const ActivitySettings(detect: true),
      );
      expect(activities.where((e) => e.id.split('/').last == 'steam'), isEmpty);
      final music = activities.where((e) => e.kind == ActivityKind.music);
      if (music.isNotEmpty) expect(music.first.iconBytes, isNotNull);
    },
    skip: Platform.environment['DELTIECORD_ACTIVITY_HOST_SMOKE'] != '1',
  );
}
