import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/video_seek_controller.dart';
import 'video_playback_status.dart';

String videoTimeLabel(Duration time) {
  final seconds = time.inSeconds.clamp(0, 999999999);
  final minutes = seconds ~/ 60;
  final tail = (seconds % 60).toString().padLeft(2, '0');
  return minutes >= 60
      ? '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:$tail'
      : '$minutes:$tail';
}

class VideoSkipGesture extends StatefulWidget {
  const VideoSkipGesture({
    required this.child,
    required this.onBack,
    required this.onForward,
    this.onTap,
    this.enabled = true,
    super.key,
  });
  final Widget child;
  final VoidCallback onBack, onForward;
  final VoidCallback? onTap;
  final bool enabled;
  @override
  State<VideoSkipGesture> createState() => _VideoSkipGestureState();
}

class _VideoSkipGestureState extends State<VideoSkipGesture> {
  Offset _tap = Offset.zero;
  bool? _forward;
  Timer? _feedback;
  @override
  void dispose() {
    _feedback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTapDown: !widget.enabled
          ? null
          : (details) => _tap = details.localPosition,
      onDoubleTap: !widget.enabled
          ? null
          : () {
              final forward = _tap.dx >= size.maxWidth / 2;
              (forward ? widget.onForward : widget.onBack)();
              _feedback?.cancel();
              setState(() => _forward = forward);
              _feedback = Timer(const Duration(milliseconds: 450), () {
                if (mounted) setState(() => _forward = null);
              });
            },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_forward case final forward?)
            IgnorePointer(
              child: Align(
                alignment: forward
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(
                        forward ? '+10s' : '−10s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// One control/gesture implementation for inline, fullscreen and embedded video.
/// Controls are siblings of the gesture surface so scrubbing cannot trigger a
/// double tap, fullscreen transition or a play/pause action behind the slider.
class VideoPlaybackOverlay extends StatefulWidget {
  const VideoPlaybackOverlay({
    required this.player,
    required this.child,
    this.onToggle,
    this.onFullscreen,
    super.key,
  });
  final Player player;
  final Widget child;
  final Future<void> Function()? onToggle;
  final VoidCallback? onFullscreen;
  @override
  State<VideoPlaybackOverlay> createState() => _VideoPlaybackOverlayState();
}

class _VideoPlaybackOverlayState extends State<VideoPlaybackOverlay> {
  late VideoSeekController _seek;
  StreamSubscription<Duration>? _position, _duration;
  double? _drag;
  void _bind() {
    _seek = VideoSeekController(
      seek: widget.player.seek,
      initialPosition: widget.player.state.position,
      initialDuration: widget.player.state.duration,
    );
    _position = widget.player.stream.position.listen(
      (value) => _seek.update(position: value),
    );
    _duration = widget.player.stream.duration.listen(
      (value) => _seek.update(duration: value),
    );
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(VideoPlaybackOverlay old) {
    super.didUpdateWidget(old);
    if (!identical(old.player, widget.player)) {
      _position?.cancel();
      _duration?.cancel();
      _seek.dispose();
      _drag = null;
      _bind();
    }
  }

  @override
  void dispose() {
    _position?.cancel();
    _duration?.cancel();
    _seek.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    // EOF can remain set until the decoder acknowledges a seek. Playing at a
    // newly selected position must not invoke the ordinary replay-from-zero.
    if (_seek.hasPendingSeek && widget.player.state.completed) {
      await _seek.seekTo(_seek.position);
      await widget.player.play();
      return;
    }
    await (widget.onToggle?.call() ?? toggleVideoPlayback(widget.player));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _seek,
    builder: (context, _) {
      final maximum = _seek.duration.inMilliseconds
          .clamp(1, 9007199254740991)
          .toDouble();
      final position = (_drag ?? _seek.position.inMilliseconds.toDouble())
          .clamp(0.0, maximum);
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: VideoSkipGesture(
              onBack: () => unawaited(_seek.skip(-10)),
              onForward: () => unawaited(_seek.skip(10)),
              onTap: () => unawaited(_toggle()),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.child,
                  VideoPlaybackStatus(
                    playing: widget.player.stream.playing,
                    completed: widget.player.stream.completed,
                    initialPlaying: widget.player.state.playing,
                    initialCompleted: widget.player.state.completed,
                    builder: (context, playing) => playing
                        ? const SizedBox.shrink()
                        : Center(
                            child: IconButton(
                              tooltip: 'Play video',
                              color: Colors.white,
                              onPressed: _toggle,
                              icon: const Icon(Icons.play_arrow, size: 36),
                            ),
                          ),
                  ),
                  StreamBuilder<bool>(
                    stream: widget.player.stream.buffering,
                    initialData: widget.player.state.buffering,
                    builder: (context, value) => value.data == true
                        ? const IgnorePointer(
                            child: Center(
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ColoredBox(
              color: Colors.black54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 22,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                      ),
                      child: Slider(
                        key: const ValueKey('video-seek-slider'),
                        value: position,
                        max: maximum,
                        onChangeStart: !_seek.canSeek
                            ? null
                            : (value) => setState(() => _drag = value),
                        onChanged: !_seek.canSeek
                            ? null
                            : (value) => setState(() => _drag = value),
                        onChangeEnd: !_seek.canSeek
                            ? null
                            : (value) {
                                unawaited(
                                  _seek.seekTo(
                                    Duration(milliseconds: value.round()),
                                  ),
                                );
                                setState(() => _drag = null);
                              },
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        VideoPlaybackStatus(
                          playing: widget.player.stream.playing,
                          completed: widget.player.stream.completed,
                          initialPlaying: widget.player.state.playing,
                          initialCompleted: widget.player.state.completed,
                          builder: (context, playing) => IconButton(
                            tooltip: playing ? 'Pause' : 'Play',
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                            ),
                            onPressed: _toggle,
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              size: 20,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '${videoTimeLabel(Duration(milliseconds: position.round()))} / ${_seek.canSeek ? videoTimeLabel(_seek.duration) : '--:--'}',
                                key: const ValueKey('video-time-label'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (widget.onFullscreen != null)
                          IconButton(
                            tooltip: 'Fullscreen',
                            color: Colors.white,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 32,
                            ),
                            onPressed: widget.onFullscreen,
                            icon: const Icon(Icons.fullscreen, size: 20),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<void> showVideoPlayerFullscreen(
  BuildContext context,
  Player player,
  VideoController controller,
) => showDialog<void>(
  context: context,
  barrierColor: Colors.black,
  builder: (context) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Positioned.fill(
          child: SafeArea(
            top: false,
            child: VideoPlaybackOverlay(
              player: player,
              child: Video(
                controller: controller,
                controls: NoVideoControls,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 8,
          child: IconButton.filledTonal(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    ),
  ),
);
