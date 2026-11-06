import 'package:media_kit/media_kit.dart';

Future<void> openRestrictedNativeVideo(Player player, Uri local) async {
  if (local.scheme != 'http' ||
      local.host != '127.0.0.1' ||
      !local.hasPort ||
      local.userInfo.isNotEmpty ||
      local.hasQuery ||
      local.hasFragment ||
      !RegExp(r'^/media/[A-Za-z0-9_-]{32}$').hasMatch(local.path)) {
    throw StateError('Embedded playback requires its validated local proxy.');
  }
  // Player.open() creates a temporary M3U and calls loadlist, which conflicts
  // with the forced video demuxer. add() uses loadfile while maintaining
  // MediaKit's normal playlist/state bookkeeping. Never relax parser safety.
  await player.stop();
  await player.add(Media(local.toString()));
  await player.jump(0);
}

Future<void> restrictNativeVideoPlayer(Player player, String format) async {
  final native = player.platform;
  if (native is! NativePlayer) throw StateError('Native player unavailable.');
  await native.setProperty('access-references', 'no');
  await native.setProperty('load-unsafe-playlists', 'no');
  await native.setProperty('demuxer-lavf-format', format);
  await native.setProperty('demuxer-lavf-o', 'protocol_whitelist=none');
}
