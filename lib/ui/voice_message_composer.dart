import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/voice_recording.dart';
import 'deltiecord_theme.dart';

/// Owns a single room's unsent recording. Amplitude updates rebuild this island
/// only, never the conversation or Matrix event stream.
class VoiceMessageComposer extends StatefulWidget {
  const VoiceMessageComposer({
    required this.backend,
    required this.roomId,
    required this.builder,
    this.replyToMessageId,
    this.onSent,
    this.createRecording,
    super.key,
  });
  final ChatBackend backend;
  final String roomId;
  final String? replyToMessageId;
  final VoidCallback? onSent;
  final VoiceRecordingController Function()? createRecording;
  final Widget Function(VoidCallback start) builder;
  @override
  State<VoiceMessageComposer> createState() => _VoiceMessageComposerState();
}

class _VoiceMessageComposerState extends State<VoiceMessageComposer>
    with WidgetsBindingObserver {
  VoiceRecordingController? _recording;
  Player? _player;
  bool _sending = false;
  bool _playing = false;
  bool _previewBusy = false;
  String? _error;
  String? _reply;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.backend.addListener(_backendChanged);
  }

  void _backendChanged() {
    if (_recording?.active == true &&
        widget.backend.voiceConnectionStatus !=
            VoiceConnectionStatus.disconnected) {
      unawaited(_recording!.stop());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_recording?.stop());
  }

  Future<void> _start() async {
    if (_recording != null) return;
    if (widget.backend.voiceConnectionStatus !=
        VoiceConnectionStatus.disconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave the call before recording a voice message.'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final recorder =
        widget.createRecording?.call() ?? VoiceRecordingController();
    setState(() {
      _recording = recorder;
      _reply = widget.replyToMessageId;
      _error = null;
    });
    await recorder.start();
    // Permission prompts and OS interruptions may background the app while
    // start awaits the platform. Do not begin recording invisibly afterwards.
    if (mounted &&
        WidgetsBinding.instance.lifecycleState != null &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      await recorder.stop();
    }
  }

  Future<void> _discard() async {
    if (_sending) return;
    await _player?.dispose();
    _player = null;
    final recording = _recording;
    if (mounted) {
      setState(() {
        _recording = null;
        _playing = false;
        _error = null;
      });
    }
    recording?.dispose();
  }

  Future<void> _preview() async {
    if (_previewBusy || _sending) return;
    _previewBusy = true;
    try {
      if (_player == null) {
        final player = _player = Player();
        player.stream.completed.listen((complete) {
          if (complete && mounted) setState(() => _playing = false);
        });
        await player.open(Media(_recording!.previewPath!), play: false);
      }
      if (!mounted || _player == null) return;
      if (_playing) {
        await _player!.pause();
      } else {
        if (_player!.state.completed) await _player!.seek(Duration.zero);
        await _player!.play();
      }
      if (mounted) setState(() => _playing = !_playing);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Preview is unavailable. The recording has not been sent.',
        );
      }
    } finally {
      _previewBusy = false;
    }
  }

  Future<void> _send() async {
    final draft = _recording?.draft;
    if (_sending || draft == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _player?.pause();
      await widget.backend.sendAttachment(
        draft,
        roomId: widget.roomId,
        replyToMessageId: _reply,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      await _discard();
      if (mounted) widget.onSent?.call();
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error =
              'Could not send. Your recording is still here; retry or delete it.';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.backend.removeListener(_backendChanged);
    unawaited(_player?.dispose());
    _recording?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    if (recording == null) return widget.builder(_start);
    return ListenableBuilder(
      listenable: recording,
      builder: (context, _) {
        final ready = recording.state == VoiceRecordingState.ready;
        final paused = recording.state == VoiceRecordingState.paused;
        final seconds = recording.elapsed.inSeconds;
        final error = _error ?? recording.error;
        return Container(
          key: const Key('voice-message-composer'),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: context.deltiecord.input,
            borderRadius: DeltiecordCorners.borderRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null)
                Padding(padding: const EdgeInsets.all(8), child: Text(error)),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Delete recording',
                    onPressed: _sending ? null : _discard,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  Text(
                    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      label: 'Recorded audio levels',
                      child: SizedBox(
                        height: 34,
                        child: CustomPaint(
                          painter: _LevelsPainter(
                            List.of(recording.recentLevels),
                            Theme.of(context).colorScheme.primary,
                            widget.backend.preferences.reducedMotion,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: ready
                        ? (_playing ? 'Pause preview' : 'Play recording')
                        : (paused ? 'Resume recording' : 'Pause recording'),
                    onPressed: _sending
                        ? null
                        : ready
                        ? _preview
                        : recording.active
                        ? recording.togglePause
                        : null,
                    icon: Icon(
                      ready
                          ? (_playing ? Icons.pause : Icons.play_arrow)
                          : paused
                          ? Icons.play_arrow
                          : Icons.pause,
                    ),
                  ),
                  IconButton(
                    tooltip: ready ? 'Send voice message' : 'Stop recording',
                    onPressed: _sending
                        ? null
                        : ready
                        ? _send
                        : recording.active
                        ? recording.stop
                        : null,
                    icon:
                        _sending ||
                            recording.state == VoiceRecordingState.starting ||
                            recording.state == VoiceRecordingState.stopping
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(ready ? Icons.send : Icons.stop),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LevelsPainter extends CustomPainter {
  _LevelsPainter(this.levels, this.color, this.reducedMotion);
  final List<double> levels;
  final Color color;
  final bool reducedMotion;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final count = max(1, (size.width / 4).floor());
    final visible = levels.skip(max(0, levels.length - count)).toList();
    for (var i = 0; i < visible.length; i++) {
      final level = reducedMotion
          ? (levels.isEmpty ? 0.0 : levels.last)
          : visible[i];
      final height = max(2.0, sqrt(level) * size.height);
      final x = reducedMotion ? i * 4.0 : size.width - (visible.length - i) * 4;
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LevelsPainter old) =>
      old.levels != levels ||
      old.color != color ||
      old.reducedMotion != reducedMotion;
}
