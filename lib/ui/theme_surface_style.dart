import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Closed, bounded painting vocabulary. No downloaded textures, shaders or code.
@immutable
class ThemeSurfaceStyle {
  const ThemeSurfaceStyle({
    this.colors = const [],
    this.border = Colors.transparent,
    this.highlight = Colors.transparent,
    this.opacity = 1,
    this.blur = 0,
    this.radius = 7,
    this.shadow = 0,
    this.texture = 0,
    this.duration = 0,
    this.horizontal = false,
    this.hover = Colors.transparent,
    this.gloss = 0,
  });
  final List<Color> colors;
  final Color border, highlight, hover;
  final double opacity, blur, radius, shadow, texture, gloss;
  final int duration;
  final bool horizontal;

  factory ThemeSurfaceStyle.parse(
    Map raw,
    Object? Function(Object?) resolve, {
    required bool highContrast,
    required bool reducedMotion,
  }) {
    Color? color(Object? v) {
      final value = resolve(v);
      if (value is Color) return value;
      if (value is! String ||
          !RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(value)) {
        return null;
      }
      return Color(
        int.parse(
          value.length == 7 ? 'ff${value.substring(1)}' : value.substring(1),
          radix: 16,
        ),
      );
    }

    double number(String key, double fallback, double min, double max) {
      final value = resolve(raw[key]);
      return value is num && value.isFinite
          ? value.toDouble().clamp(min, max)
          : fallback;
    }

    final gradient = raw['gradient'];
    final colors = gradient is List
        ? gradient.take(8).map(color).whereType<Color>().toList()
        : <Color>[];
    return ThemeSurfaceStyle(
      colors: highContrast ? const [] : List.unmodifiable(colors),
      gloss: highContrast ? 0 : number('gloss', 0, 0, .3),
      border: color(raw['border']) ?? Colors.transparent,
      highlight: highContrast
          ? Colors.transparent
          : color(raw['highlight']) ?? Colors.transparent,
      hover: color(raw['hover']) ?? Colors.transparent,
      opacity: highContrast ? 1 : number('opacity', 1, .55, 1),
      blur: highContrast || reducedMotion ? 0 : number('blur', 0, 0, 8),
      radius: number('radius', 7, 4, 18),
      shadow: highContrast ? 0 : number('shadow', 0, 0, .35),
      texture: highContrast ? 0 : number('texture', 0, 0, .08),
      duration: reducedMotion ? 0 : number('transitionMs', 0, 0, 180).round(),
      horizontal: raw['direction'] == 'horizontal',
    );
  }
}

/// Filters only the clipped popup/header, never the full scene or message list.
/// Static procedural lines replace bitmap textures and idle shader animation.
class StyledThemeSurface extends StatefulWidget {
  const StyledThemeSurface({
    required this.style,
    required this.color,
    required this.child,
    super.key,
  });
  final ThemeSurfaceStyle style;
  final Color color;
  final Widget child;
  @override
  State<StyledThemeSurface> createState() => _StyledThemeSurfaceState();
}

class _StyledThemeSurfaceState extends State<StyledThemeSurface> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.style;
    final colors = s.colors.isEmpty
        ? [widget.color, widget.color]
        : s.colors.length == 1
        ? [s.colors.first, s.colors.first]
        : s.colors;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: s.duration);
    Widget pane = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: s.horizontal ? Alignment.centerLeft : Alignment.topCenter,
          end: s.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
          colors: [
            for (final c in colors)
              Color.alphaBlend(
                _hovered ? s.hover : Colors.transparent,
                c,
              ).withValues(alpha: s.opacity),
          ],
        ),
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(s.radius),
      ),
      child: CustomPaint(
        painter: _GlassDetailPainter(s.highlight, s.texture, s.radius, s.gloss),
        child: Material(type: MaterialType.transparency, child: widget.child),
      ),
    );
    if (s.blur > 0) {
      pane = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: s.blur, sigmaY: s.blur),
        child: pane,
      );
    }
    return MouseRegion(
      onEnter: (_) {
        if (s.hover.a > 0) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (s.hover.a > 0) setState(() => _hovered = false);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s.radius),
          boxShadow: [
            if (s.shadow > 0)
              BoxShadow(
                color: Colors.black.withValues(alpha: s.shadow),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(s.radius),
          child: pane,
        ),
      ),
    );
  }
}

class _GlassDetailPainter extends CustomPainter {
  const _GlassDetailPainter(
    this.highlight,
    this.texture,
    this.radius,
    this.gloss,
  );
  final Color highlight;
  final double texture, radius, gloss;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 4 || size.height < 4) return;
    if (gloss > 0) {
      final rect = Rect.fromLTWH(0, 0, size.width, size.height * .48);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: gloss),
              Colors.white.withValues(alpha: gloss * .15),
            ],
          ).createShader(rect),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(1.5),
        Radius.circular(radius - 1),
      ),
      Paint()
        ..color = highlight
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    if (texture == 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: texture)
      ..strokeWidth = 1;
    // At most 160 strokes irrespective of display size; no timer or image decode.
    final step = ((size.width + size.height) / 160).clamp(
      12.0,
      double.infinity,
    );
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassDetailPainter old) =>
      highlight != old.highlight ||
      texture != old.texture ||
      radius != old.radius ||
      gloss != old.gloss;
}
