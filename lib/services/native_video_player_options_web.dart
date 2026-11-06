import 'package:media_kit/media_kit.dart';

Future<void> openRestrictedNativeVideo(Player player, Uri local) =>
    Future.error(
      UnsupportedError('Native playback is unavailable in browsers.'),
    );

Future<void> restrictNativeVideoPlayer(Player player, String format) =>
    Future.error(
      UnsupportedError('Native video options are unavailable in browsers.'),
    );
