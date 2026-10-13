import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'browser_lifecycle.dart' as browser;

class KeyboardGeometry {
  const KeyboardGeometry({
    required this.visible,
    required this.physicalBottom,
    this.focused = true,
    this.animating = false,
    this.physicalViewportHeight,
  });
  final bool? visible;
  final double physicalBottom;
  final bool focused, animating;
  final double? physicalViewportHeight;
  bool get settled => visible != null && focused && !animating;

  double bottomForView(double physicalHeight, double logicalHeight) {
    if (visible != true || physicalHeight <= 0) return 0;
    final bottom = physicalViewportHeight == null
        ? physicalBottom
        : math.max(0.0, physicalHeight - physicalViewportHeight!);
    return (bottom * logicalHeight / physicalHeight).clamp(0.0, logicalHeight);
  }

  static KeyboardGeometry? fromMap(Object? value) {
    if (value is! Map || value['physicalBottom'] is! num) return null;
    final bottom = (value['physicalBottom'] as num).toDouble();
    if (!bottom.isFinite || bottom < 0) return null;
    return KeyboardGeometry(
      visible: value['visible'] is bool ? value['visible'] as bool : null,
      physicalBottom: bottom,
      focused: value['focused'] == true,
      animating: value['animating'] == true,
      physicalViewportHeight:
          value['physicalViewportHeight'] is num &&
              (value['physicalViewportHeight'] as num).isFinite &&
              (value['physicalViewportHeight'] as num) > 0
          ? (value['physicalViewportHeight'] as num).toDouble()
          : null,
    );
  }
}

abstract final class MobileKeyboardGeometry {
  static const _methods = MethodChannel('net.deltie.deltiecord/composer');
  static const _events = EventChannel(
    'net.deltie.deltiecord/keyboard_geometry',
  );

  static Stream<KeyboardGeometry> get changes async* {
    if (kIsWeb) {
      yield* browser.browserKeyboardGeometryChanges
          .map(KeyboardGeometry.fromMap)
          .where((geometry) => geometry != null)
          .cast<KeyboardGeometry>();
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // Check capability before opening the stream. Older/unsupported hosts do
    // not have an EventChannel and keep Flutter's normal keyboard behaviour.
    final initial = await refresh();
    if (initial == null) return;
    yield initial;
    yield* _events
        .receiveBroadcastStream()
        .map(KeyboardGeometry.fromMap)
        .where((geometry) => geometry != null)
        .cast<KeyboardGeometry>();
  }

  static Future<KeyboardGeometry?> refresh() async {
    if (kIsWeb) {
      return KeyboardGeometry.fromMap(browser.browserKeyboardGeometry);
    }
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return KeyboardGeometry.fromMap(
        await _methods.invokeMethod<Object?>('keyboardGeometry'),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
