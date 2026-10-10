import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Encrypted attachments must finish integrity verification before decoding.
/// Give larger files time to download instead of restarting them every minute.
Duration videoStartupTimeout(int? size) =>
    Duration(seconds: (60 + ((size ?? 0) ~/ (1024 * 1024)) * 2).clamp(60, 600));

/// Some player backends retain `playing` at EOF. Completion wins for controls.
class VideoPlaybackStatus extends StatelessWidget {
  const VideoPlaybackStatus({
    required this.playing,
    required this.completed,
    required this.initialPlaying,
    required this.initialCompleted,
    required this.builder,
    super.key,
  });

  final Stream<bool> playing;
  final Stream<bool> completed;
  final bool initialPlaying;
  final bool initialCompleted;
  final Widget Function(BuildContext, bool) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: completed,
    initialData: initialCompleted,
    builder: (context, end) => StreamBuilder<bool>(
      stream: playing,
      initialData: initialPlaying,
      builder: (context, active) =>
          builder(context, active.data == true && end.data != true),
    ),
  );
}

Future<void> toggleVideoPlayback(Player player) async {
  if (player.state.completed) {
    await player.seek(Duration.zero);
    await player.play();
  } else {
    await player.playOrPause();
  }
}
