import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../services/encoded_image_dimensions.dart';
import '../services/image_animation.dart';
import '../services/image_markup.dart';
import '../services/image_preparation.dart';
import 'lifecycle_memory_image.dart' show LifecycleMemoryImage;
import 'media_edit_canvas.dart';
import 'media_editor_layout.dart';
import 'video_attachment_editor.dart';

Future<AttachmentDraft?> showAttachmentImageEditor(
  BuildContext context,
  AttachmentDraft draft, {
  AppPreferences preferences = const AppPreferences(),
}) => Navigator.of(context).push<AttachmentDraft>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => draft.mimeType.startsWith('video/')
        ? VideoAttachmentEditor(draft: draft, preferences: preferences)
        : _ImageEditor(draft: draft, preferences: preferences),
  ),
);

class _ImageEditor extends StatefulWidget {
  const _ImageEditor({required this.draft, required this.preferences});
  final AppPreferences preferences;
  final AttachmentDraft draft;
  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<_ImageEditor> {
  static const _full = Rect.fromLTWH(0, 0, 1, 1);
  Size? _size;
  Rect _crop = _full;
  int _turns = 0, _color = 0xffff5252;
  double _brush = 5;
  bool _locked = true,
      _cropMode = false,
      _drawMode = false,
      _highlighter = false,
      _busy = false,
      _loading = true,
      _showResult = false;
  double? _ratio;
  String? _error;
  AttachmentDraft? _preview;
  late ImageCompressionPreset _quality = widget.preferences.imageCompression;
  late bool _spoiler = widget.draft.spoiler;
  final _strokes = <MarkupStroke>[], _redo = <MarkupStroke>[];
  int _section = 0;

  void _select(int section) => setState(() {
    _section = section;
    _cropMode = section == 0;
    _drawMode = section == 1;
    _showResult = false;
  });

  @override
  void initState() {
    super.initState();
    _cropMode = true;
    _dimensions();
  }

  Future<void> _dimensions() async {
    final size = await readEncodedImageDimensions(
      widget.draft.bytes,
      maximumPixels: 100000000,
    );
    if (mounted) {
      setState(() {
        _loading = false;
        _size = size == null
            ? null
            : Size(size.width.toDouble(), size.height.toDouble());
        if (size == null) {
          _error =
              'This image cannot be edited here. You can still use the original.';
        }
      });
    }
  }

  void _changed() {
    _preview = null;
    _showResult = false;
    _error = null;
  }

  Size get _displaySize =>
      _turns.isOdd ? Size(_size!.height, _size!.width) : _size!;
  void _rotate() => setState(() {
    _turns = (_turns + 1) % 4;
    _crop = rotateCrop(_crop);
    if (_ratio != null) _ratio = 1 / _ratio!;
    for (final stroke in _strokes) {
      for (var i = 0; i < stroke.points.length; i++) {
        final p = stroke.points[i];
        stroke.points[i] = Offset(1 - p.dy, p.dx);
      }
    }
    _redo.clear();
    _changed();
  });
  Future<void> _render({bool save = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var draft = widget.draft.copyWith(spoiler: _spoiler);
      if (_turns != 0 || _crop != _full || _strokes.isNotEmpty) {
        final jpeg =
            draft.mimeType == 'image/jpeg' &&
            !hasAnimatedImageHeader(draft.bytes);
        final bytes = await renderMarkedImage(
          bytes: draft.bytes,
          turns: _turns,
          crop: [_crop.left, _crop.top, _crop.width, _crop.height],
          strokes: [
            for (final s in _strokes)
              {
                'color': s.color,
                'width': s.width,
                'points': [
                  for (final p in s.points) [p.dx, p.dy],
                ],
              },
          ],
          jpeg: jpeg,
          canceled: () => !mounted,
        );
        draft = draft.copyWith(
          bytes: bytes,
          mimeType: jpeg ? 'image/jpeg' : 'image/png',
          imagePrepared: false,
          name:
              '${draft.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.${jpeg ? 'jpg' : 'png'}',
        );
      }
      draft = await prepareImage(
        draft.copyWith(imagePrepared: false),
        _quality,
      );
      if (!mounted) return;
      _preview = draft.copyWith(imagePrepared: true);
      if (save) {
        Navigator.pop(context, _preview);
      } else {
        setState(() => _showResult = true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not apply these edits. Reduce the image size or cancel to keep the original.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MediaEditorTool> _tools() => [
    MediaEditorTool(
      'Crop',
      Icons.crop,
      MediaCropTools(
        locked: _locked,
        ratio: _ratio,
        onLock: (v) => setState(() {
          _locked = v;
          if (v && _size != null) {
            _crop = cropForAspect(
              _crop,
              _displaySize,
              _ratio ?? _displaySize.aspectRatio,
            );
          }
          _changed();
        }),
        onRatio: (v) => setState(() {
          _ratio = v;
          _locked = true;
          if (_size != null) {
            _crop = cropForAspect(
              _crop,
              _displaySize,
              v ?? _displaySize.aspectRatio,
            );
          }
          _changed();
        }),
        onRotate: _rotate,
        onReset: () => setState(() {
          _crop = _full;
          _changed();
        }),
      ),
    ),
    MediaEditorTool(
      'Markup',
      Icons.edit_outlined,
      Column(
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Marker'),
                icon: Icon(Icons.edit),
              ),
              ButtonSegment(
                value: true,
                label: Text('Highlighter'),
                icon: Icon(Icons.highlight),
              ),
            ],
            selected: {_highlighter},
            onSelectionChanged: (v) => setState(() => _highlighter = v.single),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final ink in const {
                0xffff5252: 'Red',
                0xffffd740: 'Yellow',
                0xff69f0ae: 'Green',
                0xff40c4ff: 'Blue',
                0xffe040fb: 'Purple',
                0xffffffff: 'White',
                0xff000000: 'Black',
              }.entries)
                Expanded(
                  child: IconButton(
                    tooltip: '${ink.value} ink',
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    constraints: const BoxConstraints(minHeight: 44),
                    onPressed: () => setState(() => _color = ink.key),
                    icon: Icon(
                      _color == ink.key ? Icons.check_circle : Icons.circle,
                      color: Color(ink.key),
                      size: 34,
                    ),
                  ),
                ),
            ],
          ),
          Row(
            children: [
              const Text('Width'),
              Expanded(
                child: Slider(
                  value: _brush,
                  min: 1,
                  max: 24,
                  onChanged: (v) => setState(() => _brush = v),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    MediaEditorTool(
      'Quality',
      Icons.hd_outlined,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                ImageCompressionPreset.original: 'Original',
                ImageCompressionPreset.balanced: 'Balanced',
                ImageCompressionPreset.smaller: 'Smaller',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _quality == entry.key,
                  onSelected: hasAnimatedImageHeader(widget.draft.bytes)
                      ? null
                      : (_) => setState(() {
                          _quality = entry.key;
                          _changed();
                        }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_preview != null)
            Text(
              '${(_preview!.bytes.length / 1048576).toStringAsFixed(2)} MiB',
            ),
          TextButton(
            onPressed: () => _render(),
            child: const Text('Preview result'),
          ),
        ],
      ),
    ),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Edit image'),
      leading: IconButton(
        tooltip: 'Cancel edits',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close),
      ),
      actions: [
        IconButton(
          tooltip: 'Undo stroke',
          onPressed: _busy || _strokes.isEmpty
              ? null
              : () => setState(() {
                  _redo.add(_strokes.removeLast());
                  _changed();
                }),
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Redo stroke',
          onPressed: _busy || _redo.isEmpty
              ? null
              : () => setState(() {
                  _strokes.add(_redo.removeLast());
                  _changed();
                }),
          icon: const Icon(Icons.redo),
        ),
        TextButton(
          onPressed: _busy || _loading
              ? null
              : () {
                  if (_size == null) {
                    Navigator.pop(
                      context,
                      widget.draft.copyWith(spoiler: _spoiler),
                    );
                  } else {
                    _render(save: true);
                  }
                },
          child: const Text('Use image'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final preview = Padding(
                  padding: EdgeInsets.zero,
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _size == null
                      ? const Center(
                          child: Icon(Icons.broken_image_outlined, size: 64),
                        )
                      : _showResult && _preview != null
                      ? Center(
                          child: LifecycleMemoryImage(
                            bytes: _preview!.bytes,
                            animated: true,
                            autoplay: !MediaQuery.disableAnimationsOf(context),
                            fit: BoxFit.contain,
                            decodeWidth: 2048,
                          ),
                        )
                      : MediaEditCanvas(
                          sourceSize: _size!,
                          turns: _turns,
                          crop: _crop,
                          cropMode: _cropMode && !_busy,
                          drawMode: _drawMode && !_busy,
                          locked: _locked,
                          ratio: _ratio,
                          strokes: _strokes,
                          brushColor: _color,
                          brushWidth: _brush,
                          onCrop: (v) => setState(() {
                            _crop = v;
                            _changed();
                          }),
                          onStroke: (p, w) => setState(() {
                            _strokes.add(
                              MarkupStroke(
                                (_color & 0x00ffffff) |
                                    (_highlighter ? 0x88000000 : 0xff000000),
                                w,
                                [p],
                              ),
                            );
                            _redo.clear();
                            _changed();
                          }),
                          onDrawPoint: (p) => setState(() {
                            if (_strokes.isNotEmpty &&
                                _strokes.last.points.length < 10000) {
                              _strokes.last.points.add(p);
                            }
                            _changed();
                          }),
                          child: LifecycleMemoryImage(
                            bytes: widget.draft.bytes,
                            animated: true,
                            autoplay:
                                !_drawMode &&
                                !_cropMode &&
                                !MediaQuery.disableAnimationsOf(context),
                            fit: BoxFit.contain,
                            decodeWidth: 2048,
                          ),
                        ),
                );
                return MediaEditorLayout(
                  preview: preview,
                  tools: _tools(),
                  selected: _section,
                  onSelect: _select,
                  spoiler: _spoiler,
                  disabled: _busy || _loading || _size == null,
                  onSpoiler: () => setState(() {
                    _spoiler = !_spoiler;
                    _changed();
                  }),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
