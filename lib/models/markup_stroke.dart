import 'dart:ui';

class MarkupStroke {
  MarkupStroke(this.color, this.width, this.points);
  final int color;
  final double width;
  final List<Offset> points;
}

/// Shared by the live canvas and exported frames, including rounded joins.
void paintMarkupStrokes(
  Canvas canvas,
  Size size,
  Iterable<MarkupStroke> strokes,
) {
  if (strokes.isEmpty) return;
  canvas.saveLayer(Offset.zero & size, Paint());
  for (final stroke in strokes) {
    final paint = Paint()
      ..color = Color(stroke.color)
      ..blendMode = stroke.color == 0 ? BlendMode.clear : BlendMode.srcOver
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
        Paint()
          ..color = paint.color
          ..blendMode = paint.blendMode,
      );
    } else if (points.isNotEmpty) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final p in points.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
  canvas.restore();
}
