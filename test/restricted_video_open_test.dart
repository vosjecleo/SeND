import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:deltiecord/services/native_video_player_options.dart';

class _Player extends Fake implements Player {
  final calls = <String>[];
  String? uri;
  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> add(Media media) async {
    calls.add('add');
    uri = media.uri;
  }

  @override
  Future<void> jump(int index) async {
    calls.add('jump:$index');
  }

  @override
  Future<void> open(Playable media, {bool play = true}) async {
    fail('The restricted path must never use MediaKit.open/loadlist');
  }
}

void main() {
  test(
    'one validated video uses supported direct-file APIs, not a temporary playlist',
    () async {
      final player = _Player();
      final uri = Uri.parse(
        'http://127.0.0.1:12345/media/abcdefghijklmnopqrstuvwxyz012345',
      );
      await openRestrictedNativeVideo(player, uri);
      expect(player.calls, ['stop', 'add', 'jump:0']);
      expect(player.uri, uri.toString());
    },
  );
  test(
    'the direct loader refuses origin URLs and non-capability loopback paths',
    () async {
      for (final url in [
        'https://video.test/movie.mp4',
        'http://127.0.0.1:12345/admin',
        'http://localhost:12345/media/abcdefghijklmnopqrstuvwxyz012345',
        'http://127.0.0.1:12345/media/abcdefghijklmnopqrstuvwxyz012345?other=true',
      ]) {
        final player = _Player();
        await expectLater(
          openRestrictedNativeVideo(player, Uri.parse(url)),
          throwsStateError,
        );
        expect(player.calls, isEmpty);
      }
    },
  );
}
