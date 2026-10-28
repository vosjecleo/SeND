import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../models/video_edit.dart';
import '../services/video_optimizer.dart';
import 'media_edit_canvas.dart';

class VideoAttachmentEditor extends StatefulWidget {
  const VideoAttachmentEditor({required this.draft, super.key});
  final AttachmentDraft draft;
  @override
  State<VideoAttachmentEditor> createState() => _VideoAttachmentEditorState();
}

class _VideoAttachmentEditorState extends State<VideoAttachmentEditor> {
  static const _full = Rect.fromLTWH(0, 0, 1, 1);
  late AttachmentDraft _probed = widget.draft;
  Player? _player;
  VideoController? _controller;
  StreamSubscription<Duration>? _position;
  RangeValues _range = const RangeValues(0, 1);
  Duration _playhead = Duration.zero;
  int _duration = 0, _turns = 0;
  bool _busy = false,
      _loading = true,
      _muted = false,
      _locked = true,
      _cropMode = false;
  Rect _crop = _full;
  double? _ratio;
  double _progress = 0;
  String _quality = 'original';
  String? _error;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final probed = await probeVideo(widget.draft);
      if (!mounted) return;
      setState(() {
        _probed = probed;
        _duration = probed.durationMilliseconds ?? 0;
        _range = RangeValues(0, math.max(1, _duration).toDouble());
      });
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      _position = player.stream.position.listen((position) {
        if (mounted) setState(() => _playhead = position);
        if (position.inMilliseconds > _range.end && _range.end > 0) {
          player.pause();
          player.seek(Duration(milliseconds: _range.start.round()));
        }
      });
      final source = await Media.memory(widget.draft.bytes);
      if (!mounted) return;
      await player.open(source, play: false);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The preview could not be opened. You can keep the original video.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _position?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Size get _size => Size(
    (_probed.videoWidth ?? 16).toDouble(),
    (_probed.videoHeight ?? 9).toDouble(),
  );
  Size get _display => _turns.isOdd ? Size(_size.height, _size.width) : _size;
  String _time(num ms) {
    final seconds = (ms / 1000).floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    final plan = VideoEditPlan(
      startMs: _range.start.round(),
      endMs: _duration > 0 && _range.end.round() < _duration
          ? _range.end.round()
          : null,
      turns: _turns,
      muted: _muted,
      left: _crop.left,
      top: _crop.top,
      width: _crop.width,
      height: _crop.height,
    );
    if (!plan.hasChanges && _quality == 'original') {
      Navigator.pop(context, widget.draft.copyWith(videoPrepared: true));
      return;
    }
    if (!videoOptimizationSupported) {
      setState(
        () => _error =
            'Video export is available in the native app. Cancel to keep the original.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });
    await _player?.pause();
    try {
      final result = await optimizeVideo(
        widget.draft,
        optimize: _quality != 'original',
        preset: VideoCompressionPreset.parse(_quality),
        edit: plan,
        canceled: () => !mounted,
        progress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (mounted) Navigator.pop(context, result.copyWith(videoPrepared: true));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not export the video. Try a shorter selection or cancel to keep the original.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _tools() => IgnorePointer(
    ignoring: _busy || _loading,
    child: Column(
      children: [
        ExpansionTile(
          title: const Text('Trim'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            Text('${_time(_range.start)} to ${_time(_range.end)}'),
            RangeSlider(
              values: _range,
              min: 0,
              max: math.max(1, _duration).toDouble(),
              onChanged: _duration <= 0
                  ? null
                  : (v) {
                      if (v.end - v.start >= 100) setState(() => _range = v);
                    },
              onChangeEnd: (v) =>
                  _player?.seek(Duration(milliseconds: v.start.round())),
            ),
            const Text('Drag the ends to choose the part to keep.'),
          ],
        ),
        MediaCropTools(
          locked: _locked,
          ratio: _ratio,
          onLock: (v) => setState(() {
            _locked = v;
            if (v) {
              _crop = cropForAspect(
                _crop,
                _display,
                _ratio ?? _display.aspectRatio,
              );
            }
          }),
          onRatio: (v) => setState(() {
            _ratio = v;
            _locked = true;
            _crop = cropForAspect(_crop, _display, v ?? _display.aspectRatio);
          }),
          onRotate: () => setState(() {
            _turns = (_turns + 1) % 4;
            _crop = rotateCrop(_crop);
            if (_ratio != null) _ratio = 1 / _ratio!;
          }),
          onReset: () => setState(() => _crop = _full),
          onExpand: (v) => setState(() => _cropMode = v),
        ),
        ExpansionTile(
          title: const Text('Audio'),
          children: [
            SwitchListTile(
              title: const Text('Mute video'),
              value: _muted,
              onChanged: (v) {
                setState(() => _muted = v);
                _player?.setVolume(v ? 0 : 100);
              },
            ),
          ],
        ),
        ExpansionTile(
          title: const Text('Quality'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _quality,
              decoration: const InputDecoration(labelText: 'Export quality'),
              items: const [
                DropdownMenuItem(
                  value: 'original',
                  child: Text('High quality'),
                ),
                DropdownMenuItem(
                  value: 'balanced',
                  child: Text('Balanced, up to 24 MiB'),
                ),
                DropdownMenuItem(
                  value: 'smaller',
                  child: Text('Smaller, up to 12 MiB'),
                ),
              ],
              onChanged: (v) => setState(() => _quality = v!),
            ),
            const SizedBox(height: 8),
            Text(
              videoOptimizationSupported
                  ? 'Editing re-encodes the clip. The original attachment stays unchanged until you use the result.'
                  : 'Video export needs the native app; browser previews do not upload your video to an editing service.',
            ),
          ],
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit video'),
      leading: IconButton(
        tooltip: 'Cancel edits',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _loading ? null : _save,
          child: const Text('Use video'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_busy) LinearProgressIndicator(value: _progress),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final preview = Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: MediaEditCanvas(
                          sourceSize: _size,
                          turns: _turns,
                          crop: _crop,
                          onCrop: (v) => setState(() => _crop = v),
                          cropMode: _cropMode && !_busy,
                          locked: _locked,
                          ratio: _ratio,
                          child: _controller != null
                              ? Video(
                                  controller: _controller!,
                                  controls: NoVideoControls,
                                )
                              : _probed.videoThumbnail != null
                              ? Image.memory(
                                  _probed.videoThumbnail!,
                                  fit: BoxFit.contain,
                                )
                              : const Center(
                                  child: Icon(Icons.movie_outlined, size: 72),
                                ),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: 'Play or pause',
                          onPressed: _busy
                              ? null
                              : () => _player?.playOrPause(),
                          icon: const Icon(Icons.play_arrow),
                        ),
                        Text(
                          '${_time(_playhead.inMilliseconds)} / ${_time(_duration)}',
                        ),
                      ],
                    ),
                  ],
                );
                if (c.maxWidth >= 850) {
                  return Row(
                    children: [
                      Expanded(child: preview),
                      SizedBox(
                        width: 340,
                        child: SingleChildScrollView(child: _tools()),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: preview),
                    SizedBox(
                      height: math.min(320, c.maxHeight * .45),
                      child: SingleChildScrollView(child: _tools()),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
