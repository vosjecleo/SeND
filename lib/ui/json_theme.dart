import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/chat_models.dart';
import 'deltiecord_theme.dart';
import 'theme_surface_style.dart';
export 'theme_surface_style.dart';
part 'theme_icons.dart';

/// A bounded, declarative document. No file/URL lookup, expressions or scripts
/// are evaluated. Future extension runtimes must have a separate trust boundary.
class JsonTheme {
  JsonTheme._(this.document);
  static const maxBytes = 65536;
  final Map<String, dynamic> document;
  String get name => document['name'] as String;
  String get id => document['id'] as String;
  List<Map<String, dynamic>> get settings =>
      (document['settings'] as List? ?? const []).cast<Map<String, dynamic>>();

  factory JsonTheme.parse(String source) {
    if (source.length > maxBytes || utf8.encode(source).length > maxBytes) {
      throw const FormatException('Theme must be at most 64 KiB.');
    }
    // Reject pathological nesting before jsonDecode or token traversal.
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (final rune in source.runes) {
      if (quoted) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (rune == 92) {
          escaped = true;
          continue;
        }
        if (rune == 34) quoted = false;
      } else if (rune == 34) {
        quoted = true;
      } else if (rune == 123 || rune == 91) {
        if (++depth > 16) {
          throw const FormatException('Theme nesting is too deep.');
        }
      } else if (rune == 125 || rune == 93) {
        depth--;
      }
    }
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value['schema'] != 1 ||
        value['id'] is! String ||
        (value['id'] as String).length > 80 ||
        value['name'] is! String ||
        (value['name'] as String).length > 80) {
      throw const FormatException(
        'Expected a schema 1 theme with id and name.',
      );
    }
    final parent = value['extends'] ?? 'gray';
    if (!const ['light', 'gray', 'regular', 'dark', 'night'].contains(parent)) {
      throw const FormatException('Theme parent must be a built-in theme.');
    }
    if (value['tokens'] != null && value['tokens'] is! Map<String, dynamic>) {
      throw const FormatException('tokens must be an object.');
    }
    final settings = value['settings'] ?? const [];
    if (settings is! List || settings.length > 20) {
      throw const FormatException('At most 20 theme settings are allowed.');
    }
    final ids = <String>{};
    for (final setting in settings) {
      if (setting is! Map<String, dynamic> ||
          setting['id'] is! String ||
          (setting['id'] as String).length > 80 ||
          !ids.add(setting['id'] as String) ||
          setting['label'] is! String ||
          (setting['label'] as String).length > 100 ||
          !const [
            'color',
            'number',
            'boolean',
            'choice',
          ].contains(setting['type'])) {
        throw const FormatException('Invalid or duplicate theme setting.');
      }
      if (setting['type'] == 'number') {
        final min = setting['min'];
        final max = setting['max'];
        if (min is! num ||
            max is! num ||
            !min.isFinite ||
            !max.isFinite ||
            min >= max ||
            min < -1000 ||
            max > 1000) {
          throw const FormatException(
            'Number settings need finite min/max bounds.',
          );
        }
      }
      if (setting['type'] == 'choice') {
        final choices = setting['choices'];
        if (choices is! List ||
            choices.isEmpty ||
            choices.length > 12 ||
            choices.any((v) => v is! String || v.length > 80)) {
          throw const FormatException(
            'Choice settings need 1–12 short labels.',
          );
        }
      }
    }
    if (value['variants'] != null &&
        value['variants'] is! Map<String, dynamic>) {
      throw const FormatException('variants must be an object.');
    }
    return JsonTheme._(value);
  }

  Map<String, Object?> values(Map<String, Object?> overrides) => {
    for (final setting in settings)
      setting['id'] as String: _value(setting, overrides[setting['id']]),
  };

  Object _value(Map<String, dynamic> setting, Object? override) {
    final value = override ?? setting['default'];
    switch (setting['type']) {
      case 'color':
        return parseThemeColor(value) != null ? value! : '#6975d9';
      case 'boolean':
        return value is bool ? value : false;
      case 'number':
        final min = (setting['min'] as num).toDouble();
        final max = (setting['max'] as num).toDouble();
        return value is num && value.isFinite
            ? value.toDouble().clamp(min, max)
            : min;
      case 'choice':
        final choices = setting['choices'] as List;
        return choices.contains(value) ? value! : choices.first as String;
      default:
        return false;
    }
  }

  ResolvedJsonTheme resolve(AppPreferences preferences) {
    final parameters = values(preferences.themeSettings);
    final variant = (document['variants'] as Map?)?[parameters['variant']];
    final parent = variant is Map
        ? variant['extends'] ?? document['extends']
        : document['extends'];
    final mode = switch (parent) {
      'light' => DeltiecordThemeMode.light,
      'dark' => DeltiecordThemeMode.dark,
      'night' => DeltiecordThemeMode.night,
      _ => DeltiecordThemeMode.regular,
    };
    final base = DeltiecordPalette.forMode(mode);
    final tokens = <String, dynamic>{
      ...?document['tokens'] as Map<String, dynamic>?,
      if (variant is Map && variant['tokens'] is Map)
        ...Map<String, dynamic>.from(variant['tokens'] as Map),
    };
    final defaults = <String, Object>{
      'surface.background': base.background,
      'surface.rail': base.rail,
      'surface.panel': base.panel,
      'surface.content': base.surface,
      'surface.raised': base.elevated,
      'surface.input': base.input,
      'surface.island': base.island,
      'surface.hover': base.hover,
      'border.subtle': base.divider,
      'text.primary': base.text,
      'text.secondary': base.muted,
      'accent.primary': Color(preferences.accentColor),
      'accent.secondary': Color(preferences.accentColor),
      'selection.fill': Color(preferences.accentColor).withValues(alpha: .13),
      'selection.border': Colors.transparent,
      'glass.opacity': 1.0,
      'glass.blur': 0.0,
      'glass.gloss': 0.0,
      'glass.glow': 0.0,
      'shape.cardRadius': 12.0,
      'icons.style': 'Outline',
      'icons.pack': 'Material',
      'avatar.shape': 'circle',
    };
    var remainingExpressions = 2048;
    Object? expression(Object? value, Set<String> visiting) {
      if (--remainingExpressions < 0) return null;
      if (value is Map) {
        if (value['setting'] is String) return parameters[value['setting']];
        if (value['ref'] is String) {
          final ref = value['ref'] as String;
          if (visiting.contains(ref) || visiting.length >= 16) {
            return defaults[ref];
          }
          return expression(tokens[ref] ?? defaults[ref], {...visiting, ref});
        }
        if (value['mix'] is List && (value['mix'] as List).length == 2) {
          final pair = value['mix'] as List;
          final a = parseThemeColor(expression(pair[0], visiting));
          final b = parseThemeColor(expression(pair[1], visiting));
          final amount = expression(value['amount'], visiting);
          if (a != null && b != null && amount is num && amount.isFinite) {
            return Color.lerp(a, b, amount.toDouble().clamp(0, 1));
          }
        }
        return null;
      }
      return value;
    }

    Object? token(String key) =>
        expression(tokens[key] ?? defaults[key], {key});
    Color color(String key) =>
        parseThemeColor(token(key)) ?? defaults[key] as Color;
    double number(String key, double min, double max) {
      final v = token(key);
      return v is num && v.isFinite
          ? v.toDouble().clamp(min, max)
          : defaults[key] as double;
    }

    // Core surfaces/text stay opaque. Transparency belongs to bounded chrome,
    // never to an entire message list or inherited text opacity.
    Color opaque(String key) => color(key).withValues(alpha: 1);
    final rawSurfaces = <String, dynamic>{
      if (document['surfaces'] is Map)
        ...Map<String, dynamic>.from(document['surfaces'] as Map),
      if (variant is Map && variant['surfaces'] is Map)
        ...Map<String, dynamic>.from(variant['surfaces'] as Map),
    };
    final surfaces = <String, ThemeSurfaceStyle>{};
    for (final name in const ['header', 'popup', 'island', 'button']) {
      final raw = rawSurfaces[name];
      if (raw is Map) {
        surfaces[name] = ThemeSurfaceStyle.parse(
          raw,
          (v) => expression(v, {}),
          highContrast: preferences.highContrast,
          reducedMotion: preferences.reducedMotion,
        );
      }
    }
    return ResolvedJsonTheme(
      palette: base.copyWith(
        background: opaque('surface.background'),
        rail: opaque('surface.rail'),
        panel: opaque('surface.panel'),
        surface: opaque('surface.content'),
        elevated: opaque('surface.raised'),
        input: opaque('surface.input'),
        island: opaque('surface.island'),
        hover: opaque('surface.hover'),
        divider: color('border.subtle'),
        text: opaque('text.primary'),
        muted: opaque('text.secondary'),
      ),
      accent: opaque('accent.primary'),
      secondary: opaque('accent.secondary'),
      brightness: mode == DeltiecordThemeMode.light
          ? Brightness.light
          : Brightness.dark,
      chrome: ThemeChrome(
        classicIcons: token('icons.style') == 'Classic',
        iconPack: token('icons.pack') == 'Tango' ? 'Tango' : 'Material',
        customIcons: parseThemeIcons(document['icons']),
        glassAvatars:
            token('avatar.shape') == 'glass-square' &&
            !preferences.highContrast,
        surfaces: Map.unmodifiable(surfaces),
        selection: color('selection.fill'),
        selectionBorder: color('selection.border'),
        opacity: preferences.highContrast ? 1 : number('glass.opacity', .65, 1),
        blur: preferences.highContrast || preferences.reducedMotion
            ? 0
            : number('glass.blur', 0, 8),
        gloss: preferences.highContrast ? 0 : number('glass.gloss', 0, .3),
        glow: preferences.highContrast ? 0 : number('glass.glow', 0, .15),
        radius: number('shape.cardRadius', 4, 18),
      ),
    );
  }

  static ResolvedJsonTheme? fromPreferences(AppPreferences preferences) {
    if (preferences.themeJson.isEmpty) return null;
    try {
      return JsonTheme.parse(preferences.themeJson).resolve(preferences);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}

Color? parseThemeColor(Object? value) {
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

class ResolvedJsonTheme {
  const ResolvedJsonTheme({
    required this.palette,
    required this.accent,
    required this.secondary,
    required this.brightness,
    required this.chrome,
  });
  final DeltiecordPalette palette;
  final Color accent;
  final Color secondary;
  final Brightness brightness;
  final ThemeChrome chrome;
}

@immutable
class ThemeChrome extends ThemeExtension<ThemeChrome> {
  const ThemeChrome({
    this.selection,
    this.selectionBorder = Colors.transparent,
    this.opacity = 1,
    this.blur = 0,
    this.gloss = 0,
    this.glow = 0,
    this.radius = 12,
    this.surfaces = const {},
    this.classicIcons = false,
    this.glassAvatars = false,
    this.iconPack = 'Material',
    this.customIcons = const {},
  });
  final Color? selection;
  final Color selectionBorder;
  final double opacity, blur, gloss, glow, radius;
  final Map<String, ThemeSurfaceStyle> surfaces;
  final bool classicIcons;
  final bool glassAvatars;
  final String iconPack;
  final Map<String, Uint8List> customIcons;
  @override
  ThemeChrome copyWith() => this;
  @override
  ThemeChrome lerp(covariant ThemeChrome? other, double t) =>
      t < .5 ? this : other ?? this;
}

/// Glass is explicitly opt-in and clipped to a static panel. Do not wrap
/// scrolling timelines or individual messages in backdrop filters.
class ThemeSurface extends StatelessWidget {
  const ThemeSurface({
    required this.child,
    required this.color,
    this.kind = 'header',
    super.key,
  });
  final Widget child;
  final Color color;
  final String kind;
  static Widget wrap(
    BuildContext context, {
    required String kind,
    required Color color,
    required Widget child,
  }) {
    final style = Theme.of(context).extension<ThemeChrome>()?.surfaces[kind];
    return style == null
        ? child
        : StyledThemeSurface(style: style, color: color, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final fx =
        Theme.of(context).extension<ThemeChrome>() ?? const ThemeChrome();
    final style = fx.surfaces[kind];
    if (style != null) {
      return StyledThemeSurface(style: style, color: color, child: child);
    }
    if (kind != 'header') return Material(color: color, child: child);
    if (fx.gloss == 0 && fx.blur == 0 && fx.opacity == 1 && fx.glow == 0) {
      return ColoredBox(color: color, child: child);
    }
    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(
              Colors.white.withValues(alpha: fx.gloss),
              color.withValues(alpha: fx.opacity),
            ),
            color.withValues(alpha: fx.opacity),
            color.withValues(alpha: fx.opacity),
          ],
          stops: const [0, .48, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: fx.gloss * .65),
        ),
        boxShadow: [
          if (fx.glow > 0)
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: fx.glow),
              blurRadius: 10,
            ),
        ],
      ),
      child: child,
    );
    if (fx.blur > 0) {
      pane = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: fx.blur, sigmaY: fx.blur),
        child: pane,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(fx.radius),
      child: pane,
    );
  }
}

/// Theme-aware avatar geometry; image providers/cache keys remain unchanged.
class ThemeAvatar extends StatelessWidget {
  const ThemeAvatar({
    this.radius,
    this.backgroundImage,
    this.backgroundColor,
    this.child,
    super.key,
  });
  final double? radius;
  final ImageProvider? backgroundImage;
  final Color? backgroundColor;
  final Widget? child;
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).extension<ThemeChrome>()?.glassAvatars != true) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: backgroundImage,
        backgroundColor: backgroundColor,
        child: child,
      );
    }
    return SizedBox.square(
      dimension: (radius ?? 20) * 2,
      child: ThemeAvatarClip(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                backgroundColor ??
                Theme.of(context).colorScheme.surfaceContainerHighest,
            image: backgroundImage == null
                ? null
                : DecorationImage(image: backgroundImage!, fit: BoxFit.cover),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class ThemeAvatarClip extends StatelessWidget {
  const ThemeAvatarClip({
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });
  final Widget child;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).extension<ThemeChrome>()?.glassAvatars != true) {
      return ClipOval(clipBehavior: clipBehavior, child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0x99FFFFFF)),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x55FFFFFF),
                      Color(0x12FFFFFF),
                      Colors.transparent,
                      Color(0x18002040),
                    ],
                    stops: [0, .48, .49, 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
