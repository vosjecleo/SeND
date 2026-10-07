import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/secret_redaction.dart';
import 'deltiecord_theme.dart';

/// Shared, lazy audio playback for files and Matrix voice messages.
class AudioAttachmentPlayer extends StatefulWidget {
  const AudioAttachmentPlayer({
    required this.backend,
    required this.messageId,
    required this.attachment,
    required this.onSave,
    this.createPlayer,
    super.key,
  });
  final ChatBackend backend;
  final String messageId;
  final ChatAttachment attachment;
  final VoidCallback onSave;
  @visibleForTesting
  final Player Function()? createPlayer;

  @override
  State<AudioAttachmentPlayer> createState() => _AudioAttachmentPlayerState();
}

class _AudioAttachmentPlayerState extends State<AudioAttachmentPlayer>
    with WidgetsBindingObserver {
  Player? _player;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _opening = false;
  bool _playing = false;
  bool _completed = false;
  bool _retained = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_player?.pause());
    }
  }

  Future<void> _toggle() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (_player case final player?) {
        if (player.state.completed) {
          setState(() {
            _completed = false;
            _position = Duration.zero;
          });
          await player.seek(Duration.zero);
          await player.play();
        } else {
          await player.playOrPause();
        }
        return;
      }
      final source = await widget.backend.getMediaPlaybackSource(
        widget.messageId,
      );
      if (source == null) throw StateError('Audio playback is unavailable.');
      if (!mounted) {
        await widget.backend.releaseMediaPlaybackSource(widget.messageId);
        return;
      }
      _retained = true;
      final player = _player = widget.createPlayer?.call() ?? Player();
      _subscriptions.addAll([
        player.stream.playing.listen((value) {
          if (mounted) setState(() => _playing = value);
        }),
        player.stream.position.listen((value) {
          if (mounted) setState(() => _position = value);
        }),
        player.stream.duration.listen((value) {
          if (mounted) setState(() => _duration = value);
        }),
        player.stream.completed.listen((value) {
          if (mounted) setState(() => _completed = value);
        }),
        player.stream.error.listen((value) {
          if (mounted) setState(() => _error = safeErrorMessage(value));
        }),
      ]);
      await player.open(
        Media(source.uri.toString(), httpHeaders: source.headers),
      );
    } catch (error) {
      // Disposal owns the player and retained media once the row leaves the
      // tree; an in-flight open must not dispose/release them a second time.
      if (!mounted) return;
      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();
      final player = _player;
      _player = null;
      if (player != null) await player.dispose();
      if (_retained) {
        _retained = false;
        await widget.backend.releaseMediaPlaybackSource(widget.messageId);
      }
      if (mounted) setState(() => _error = safeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final player = _player;
    final backend = widget.backend;
    final id = widget.messageId;
    final retained = _retained;
    unawaited(() async {
      if (player != null) await player.dispose();
      if (retained) await backend.releaseMediaPlaybackSource(id);
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final duration = _duration > Duration.zero
        ? _duration
        : Duration(
            milliseconds: math.max(0, attachment.durationMilliseconds ?? 0),
          );
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: context.deltiecord.elevated,
        borderRadius: DeltiecordCorners.borderRadius,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: _playing ? 'Pause audio' : 'Play audio',
            onPressed: _opening ? null : _toggle,
            icon: _opening
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!attachment.voiceMessage)
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                AudioProgress(
                  // Position streams may end a few milliseconds before EOF.
                  // Only the player's completion event fills the final bars.
                  position: _completed ? duration : _position,
                  duration: duration,
                  waveform: attachment.waveform,
                  onSeek: _player == null || duration <= Duration.zero
                      ? null
                      : (value) {
                          setState(() {
                            _completed = false;
                            _position = value;
                          });
                          unawaited(_player!.seek(value));
                        },
                ),
                if (_error case final error?)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Download audio',
            onPressed: widget.onSave,
            icon: const Icon(Icons.download, size: 20),
          ),
        ],
      ),
    );
  }
}

String audioTime(Duration value) {
  final seconds = math.max(0, value.inSeconds);
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final tail = (seconds % 60).toString().padLeft(2, '0');
  if (seconds < 3600) return '$minutes:$tail';
  return '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:$tail';
}

/// Real supplied amplitude samples; uniform bars when the file has no waveform.
/// No timeline-wide timer or eager media download is needed for idle players.
class AudioProgress extends StatelessWidget {
  const AudioProgress({
    required this.position,
    required this.duration,
    required this.waveform,
    this.onSeek,
    super.key,
  });
  final Duration position;
  final Duration duration;
  final List<int> waveform;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final total = math.max(0, duration.inMilliseconds);
    final elapsed = position.inMilliseconds.clamp(0, total);
    final fraction = total == 0 ? 0.0 : elapsed / total;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            void seek(double x) => onSeek?.call(
              Duration(
                milliseconds:
                    (total *
                            (x / math.max(1, constraints.maxWidth)).clamp(0, 1))
                        .round(),
              ),
            );
            return Semantics(
              label: 'Audio progress',
              value: '${audioTime(position)} of ${audioTime(duration)}',
              increasedValue: onSeek == null
                  ? null
                  : audioTime(
                      Duration(milliseconds: math.min(total, elapsed + 5000)),
                    ),
              decreasedValue: onSeek == null
                  ? null
                  : audioTime(
                      Duration(milliseconds: math.max(0, elapsed - 5000)),
                    ),
              onIncrease: onSeek == null
                  ? null
                  : () => onSeek!(
                      Duration(milliseconds: math.min(total, elapsed + 5000)),
                    ),
              onDecrease: onSeek == null
                  ? null
                  : () => onSeek!(
                      Duration(milliseconds: math.max(0, elapsed - 5000)),
                    ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: onSeek == null
                    ? null
                    : (details) => seek(details.localPosition.dx),
                onHorizontalDragUpdate: onSeek == null
                    ? null
                    : (details) => seek(details.localPosition.dx),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 40),
                  painter: _WaveformPainter(
                    waveform,
                    fraction,
                    Theme.of(context).colorScheme.primary,
                    context.deltiecord.muted.withValues(alpha: .4),
                  ),
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(audioTime(Duration(milliseconds: elapsed))),
            Text(duration > Duration.zero ? audioTime(duration) : '--:--'),
          ],
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(
    this.samples,
    this.progress,
    this.played,
    this.remaining,
  );
  final List<int> samples;
  final double progress;
  final Color played, remaining;
  @override
  void paint(Canvas canvas, Size size) {
    final count = math.max(1, (size.width / 5).floor());
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final amplitude = samples.isEmpty
          ? .45
          : samples[(i * samples.length ~/ count).clamp(0, samples.length - 1)]
                    .clamp(0, 1024) /
                1024;
      final height = 4 + amplitude * (size.height - 10);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * size.width / count,
          (size.height - height) / 2,
          3,
          height,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, paint..color = remaining);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      canvas.drawRRect(rect, paint..color = played);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.samples != samples ||
      old.played != played ||
      old.remaining != remaining;
}
