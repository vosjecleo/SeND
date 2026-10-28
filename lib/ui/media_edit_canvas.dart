import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MarkupStroke {
  MarkupStroke(this.color, this.width, this.points);
  final int color;
  final double width;
  final List<Offset> points;
}

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
    this.locked = true,
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
  Rect _startCrop = const Rect.fromLTWH(0, 0, 1, 1);
  Offset _start = Offset.zero, _anchor = Offset.zero;
  String _handle = 'move';
  Size _paintSize = Size.zero;
  Offset _point(Offset p) => Offset(
    (p.dx / _paintSize.width).clamp(0, 1),
    (p.dy / _paintSize.height).clamp(0, 1),
  );
  void _startDrag(DragStartDetails details) {
    final point = _point(details.localPosition);
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
    for (final entry in corners.entries) {
      if ((Offset(
                    entry.value.dx * _paintSize.width,
                    entry.value.dy * _paintSize.height,
                  ) -
                  details.localPosition)
              .distance <
          28) {
        _handle = entry.key;
        break;
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
        Size(constraints.maxWidth, constraints.maxHeight),
      ).destination;
      _paintSize = fitted;
      return Center(
        child: SizedBox(
          width: fitted.width,
          height: fitted.height,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            key: const ValueKey('media-editor-canvas'),
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.cropMode || widget.drawMode ? _startDrag : null,
            onPanUpdate: widget.cropMode || widget.drawMode ? _drag : null,
            onTapUp: widget.drawMode
                ? (details) => widget.onStroke?.call(
                    _point(details.localPosition),
                    widget.brushWidth / fitted.shortestSide,
                  )
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RotatedBox(quarterTurns: widget.turns, child: widget.child),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _EditOverlay(
                      widget.crop,
                      widget.cropMode,
                      widget.strokes,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EditOverlay extends CustomPainter {
  _EditOverlay(this.crop, this.handles, this.strokes);
  final Rect crop;
  final bool handles;
  final List<MarkupStroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = stroke.width * size.shortestSide
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final points = stroke.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height))
          .toList();
      if (points.length == 1) {
        canvas.drawCircle(
          points.first,
          paint.strokeWidth / 2,
          Paint()..color = paint.color,
        );
      } else if (points.isNotEmpty) {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
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
        canvas.drawCircle(p, 6, Paint()..color = Colors.white);
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
    required this.onExpand,
    this.controller,
    super.key,
  });
  final bool locked;
  final ExpansibleController? controller;
  final double? ratio;
  final ValueChanged<bool> onLock, onExpand;
  final ValueChanged<double?> onRatio;
  final VoidCallback onRotate, onReset;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    controller: controller,
    title: const Text('Crop & rotate'),
    onExpansionChanged: onExpand,
    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Lock aspect ratio'),
        value: locked,
        onChanged: onLock,
      ),
      DropdownButtonFormField<double>(
        key: ValueKey(ratio),
        initialValue: ratio ?? 0,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Aspect ratio'),
        items: [
          const DropdownMenuItem(value: 0, child: Text('Original ratio')),
          for (final entry in <double, String>{
            1: 'Square, 1:1',
            4 / 3: 'Landscape, 4:3',
            3 / 4: 'Portrait, 3:4',
            16 / 9: 'Wide, 16:9',
            9 / 16: 'Tall, 9:16',
            4 / 5: 'Portrait, 4:5',
            5 / 4: 'Landscape, 5:4',
          }.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: (v) => onRatio(v == 0 ? null : v),
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
