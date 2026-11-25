import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

export '../models/markup_stroke.dart';
import '../models/markup_stroke.dart';
import 'editor_captions.dart';

Rect cropForAspect(Rect crop, Size size, double ratio) {
  final normalized = ratio * size.height / size.width;
  var width = crop.width, height = crop.height;
  if (width / height > normalized) {
    width = height * normalized;
  } else {
    height = width / normalized;
  }
  return Rect.fromLTWH(
    (crop.center.dx - width / 2).clamp(0, 1 - width),
    (crop.center.dy - height / 2).clamp(0, 1 - height),
    width,
    height,
  );
}

Rect rotateCrop(Rect crop) => Rect.fromLTWH(
  (1 - crop.bottom).clamp(0, 1),
  crop.left.clamp(0, 1),
  crop.height,
  crop.width,
);

class MediaEditCanvas extends StatefulWidget {
  const MediaEditCanvas({
    required this.child,
    required this.sourceSize,
    required this.turns,
    required this.crop,
    required this.onCrop,
    this.cropMode = false,
    this.drawMode = false,
    this.locked = false,
    this.captions = const [],
    this.onPlace,
    this.ratio,
    this.strokes = const [],
    this.onStroke,
    this.onDrawPoint,
    this.brushColor = 0xffff5252,
    this.brushWidth = 5,
    super.key,
  });
  final Widget child;
  final Size sourceSize;
  final int turns;
  final Rect crop;
  final ValueChanged<Rect> onCrop;
  final List<EditorCaption> captions;
  final ValueChanged<Offset>? onPlace;
  final bool cropMode, drawMode, locked;
  final double? ratio;
  final List<MarkupStroke> strokes;
  final void Function(Offset point, double normalizedWidth)? onStroke;
  final ValueChanged<Offset>? onDrawPoint;
  final int brushColor;
  final double brushWidth;
  @override
  State<MediaEditCanvas> createState() => _MediaEditCanvasState();
}

class _MediaEditCanvasState extends State<MediaEditCanvas> {
  double _zoom = 1, _baseZoom = 1;
  Offset _shift = Offset.zero,
      _baseShift = Offset.zero,
      _baseFocus = Offset.zero;
  final _viewport = GlobalKey();
  Offset _focus(Offset global) {
    final box = _viewport.currentContext!.findRenderObject()! as RenderBox;
    return box.globalToLocal(global) - box.size.center(Offset.zero);
  }

  void _magnify(
    double zoom,
    Offset oldFocus,
    Offset newFocus,
    double previous,
    Offset shift,
  ) {
    final next = zoom.clamp(1.0, 5.0);
    final translated = newFocus - (oldFocus - shift) * (next / previous);
    final limit =
        Offset(_paintSize.width, _paintSize.height) * ((next - 1) / 2);
    setState(() {
      _zoom = next;
      _shift = Offset(
        translated.dx.clamp(-limit.dx, limit.dx),
        translated.dy.clamp(-limit.dy, limit.dy),
      );
    });
  }

  bool _pinched = false, _editing = false;
  final _pointers = <int>{};
  Offset _editPosition(Offset global) =>
      (_focus(global) - _shift) / _zoom +
      Offset(_paintSize.width / 2 + 28, _paintSize.height / 2 + 28);

  bool _canEditAt(Offset point) {
    final image = const Offset(28, 28) & _paintSize;
    if (widget.onPlace != null || widget.drawMode) return image.contains(point);
    return widget.cropMode && image.inflate(28).contains(point);
  }

  Rect _startCrop = const Rect.fromLTWH(0, 0, 1, 1);
  Offset _start = Offset.zero, _anchor = Offset.zero;
  String _handle = 'move';
  Size _paintSize = Size.zero;
  Offset _point(Offset p) => Offset(
    ((p.dx - 28) / _paintSize.width).clamp(0, 1),
    ((p.dy - 28) / _paintSize.height).clamp(0, 1),
  );
  void _startDrag(DragStartDetails details) {
    final point = _point(details.localPosition);
    if (widget.onPlace != null) {
      widget.onPlace!(point);
      return;
    }
    if (widget.drawMode) {
      widget.onStroke?.call(point, widget.brushWidth / _paintSize.shortestSide);
      return;
    }
    _start = point;
    _startCrop = widget.crop;
    final corners = {
      'lt': widget.crop.topLeft,
      'rt': widget.crop.topRight,
      'lb': widget.crop.bottomLeft,
      'rb': widget.crop.bottomRight,
    };
    _handle = 'move';
    var closest = 40.0;
    for (final entry in corners.entries) {
      final distance =
          (Offset(
                    entry.value.dx * _paintSize.width + 28,
                    entry.value.dy * _paintSize.height + 28,
                  ) -
                  details.localPosition)
              .distance;
      if (distance < closest) {
        closest = distance;
        _handle = entry.key;
      }
    }
    if (_handle == 'move' && !widget.crop.contains(point)) _handle = 'new';
    _anchor = switch (_handle) {
      'lt' => widget.crop.bottomRight,
      'rt' => widget.crop.bottomLeft,
      'lb' => widget.crop.topRight,
      'rb' => widget.crop.topLeft,
      _ => point,
    };
  }

  void _drag(DragUpdateDetails details) {
    final p = _point(details.localPosition);
    if (widget.onPlace != null) {
      widget.onPlace!(p);
      return;
    }
    if (widget.drawMode) {
      widget.onDrawPoint?.call(p);
      return;
    }
    if (_handle == 'move') {
      final delta = p - _start;
      widget.onCrop(
        Rect.fromLTWH(
          (_startCrop.left + delta.dx).clamp(0, 1 - _startCrop.width),
          (_startCrop.top + delta.dy).clamp(0, 1 - _startCrop.height),
          _startCrop.width,
          _startCrop.height,
        ),
      );
      return;
    }
    final sx = p.dx >= _anchor.dx ? 1.0 : -1.0,
        sy = p.dy >= _anchor.dy ? 1.0 : -1.0;
    final availableW = sx > 0 ? 1 - _anchor.dx : _anchor.dx,
        availableH = sy > 0 ? 1 - _anchor.dy : _anchor.dy;
    var width = math.max(.02, (p.dx - _anchor.dx).abs()),
        height = math.max(.02, (p.dy - _anchor.dy).abs());
    if (widget.locked) {
      final display = widget.turns.isOdd
          ? Size(widget.sourceSize.height, widget.sourceSize.width)
          : widget.sourceSize;
      final ratio =
          (widget.ratio ?? display.aspectRatio) *
          display.height /
          display.width;
      width = math.max(width, height * ratio);
      height = width / ratio;
      final factor = math.min(
        1.0,
        math.min(availableW / width, availableH / height),
      );
      width *= factor;
      height *= factor;
    } else {
      width = math.min(width, availableW);
      height = math.min(height, availableH);
    }
    if (width < .005 || height < .005) return;
    widget.onCrop(
      Rect.fromLTWH(
        sx > 0 ? _anchor.dx : _anchor.dx - width,
        sy > 0 ? _anchor.dy : _anchor.dy - height,
        width,
        height,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = widget.turns.isOdd
          ? Size(widget.sourceSize.height, widget.sourceSize.width)
          : widget.sourceSize;
      final fitted = applyBoxFit(
        BoxFit.contain,
        size,
        Size(
          math.max(1, constraints.maxWidth - 56),
          math.max(1, constraints.maxHeight - 56),
        ),
      ).destination;
      _paintSize = fitted;
      return ClipRect(
        key: _viewport,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointers.isEmpty) _pinched = false;
            _pointers.add(event.pointer);
            if (_pointers.length > 1) _pinched = true;
          },
          onPointerUp: (event) => _pointers.remove(event.pointer),
          onPointerCancel: (event) => _pointers.remove(event.pointer),
          onPointerPanZoomStart: (_) => _pinched = true,
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              GestureBinding.instance.pointerSignalResolver.register(signal, (
                _,
              ) {
                final focus = _focus(signal.position);
                _magnify(
                  _zoom * math.exp(-signal.scrollDelta.dy * .002),
                  focus,
                  focus,
                  _zoom,
                  _shift,
                );
              });
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onScaleStart: (d) {
              _baseZoom = _zoom;
              _baseFocus = _focus(d.focalPoint);
              _baseShift = _shift;
              _pinched = _pinched || d.pointerCount > 1;
              final point = _editPosition(d.focalPoint);
              _editing = !_pinched && _canEditAt(point);
              if (_editing) {
                _startDrag(
                  DragStartDetails(
                    localPosition: point,
                    globalPosition: d.focalPoint,
                  ),
                );
              }
            },
            onScaleUpdate: (d) {
              if (d.pointerCount > 1) {
                _pinched = true;
                _magnify(
                  _baseZoom * d.scale,
                  _baseFocus,
                  _focus(d.focalPoint),
                  _baseZoom,
                  _baseShift,
                );
              } else if (!_pinched && _editing) {
                _drag(
                  DragUpdateDetails(
                    localPosition: _editPosition(d.focalPoint),
                    globalPosition: d.focalPoint,
                  ),
                );
              }
            },
            onTapUp: widget.onPlace != null || widget.drawMode
                ? (d) {
                    final point = _editPosition(d.globalPosition);
                    if (_pinched || !_canEditAt(point)) return;
                    if (widget.onPlace != null) {
                      widget.onPlace!(_point(point));
                    } else {
                      widget.onStroke?.call(
                        _point(point),
                        widget.brushWidth / fitted.shortestSide,
                      );
                    }
                  }
                : null,
            child: Center(
              child: Transform.translate(
                offset: _shift,
                child: Transform.scale(
                  scale: _zoom,
                  child: SizedBox(
                    key: const ValueKey('media-editor-canvas'),
                    width: fitted.width + 56,
                    height: fitted.height + 56,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RotatedBox(
                            quarterTurns: widget.turns,
                            child: widget.child,
                          ),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _EditOverlay(
                                widget.crop,
                                widget.cropMode,
                                widget.strokes,
                                widget.captions,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _EditOverlay extends CustomPainter {
  _EditOverlay(this.crop, this.handles, this.strokes, this.captions);
  final List<EditorCaption> captions;
  final Rect crop;
  final bool handles;
  final List<MarkupStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    paintMarkupStrokes(canvas, size, strokes);
    paintCaptions(canvas, size, captions);
    final r = Rect.fromLTWH(
      crop.left * size.width,
      crop.top * size.height,
      crop.width * size.width,
      crop.height * size.height,
    );
    if (handles || crop != const Rect.fromLTWH(0, 0, 1, 1)) {
      canvas.drawPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(r),
        Paint()..color = const Color(0x99000000),
      );
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
    if (handles) {
      final grid = Paint()
        ..color = const Color(0x88ffffff)
        ..strokeWidth = 1;
      for (final n in [1, 2]) {
        canvas.drawLine(
          Offset(r.left + r.width * n / 3, r.top),
          Offset(r.left + r.width * n / 3, r.bottom),
          grid,
        );
        canvas.drawLine(
          Offset(r.left, r.top + r.height * n / 3),
          Offset(r.right, r.top + r.height * n / 3),
          grid,
        );
      }
      for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
        canvas.drawCircle(p, 9, Paint()..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(_EditOverlay old) => true;
}

class MediaCropTools extends StatelessWidget {
  const MediaCropTools({
    required this.locked,
    required this.ratio,
    required this.onLock,
    required this.onRatio,
    required this.onRotate,
    required this.onReset,
    super.key,
  });
  final bool locked;
  final double? ratio;
  final ValueChanged<bool> onLock;
  final ValueChanged<double?> onRatio;
  final VoidCallback onRotate, onReset;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: const Text('Lock aspect ratio'),
        value: locked,
        onChanged: onLock,
      ),
      if (MediaQuery.sizeOf(context).width < 850)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: DropdownButtonFormField<double>(
            key: ValueKey(ratio),
            initialValue: ratio ?? 0,
            isExpanded: true,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Aspect ratio',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final entry in <double, String>{
                0: 'Original',
                1: '1:1',
                4 / 3: '4:3',
                3 / 4: '3:4',
                16 / 9: '16:9',
                9 / 16: '9:16',
                4 / 5: '4:5',
                5 / 4: '5:4',
              }.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => onRatio(value == 0 ? null : value),
          ),
        )
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final entry in <double, String>{
              0: 'Original',
              1: '1:1',
              4 / 3: '4:3',
              3 / 4: '3:4',
              16 / 9: '16:9',
              9 / 16: '9:16',
              4 / 5: '4:5',
              5 / 4: '5:4',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: (ratio ?? 0) == entry.key,
                onSelected: (_) => onRatio(entry.key == 0 ? null : entry.key),
              ),
          ],
        ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: onRotate,
            icon: const Icon(Icons.rotate_right),
            label: const Text('Rotate'),
          ),
          TextButton(onPressed: onReset, child: const Text('Reset crop')),
        ],
      ),
    ],
  );
}
