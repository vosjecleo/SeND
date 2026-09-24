import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

web.HTMLElement? _probe;
(int, int)? _viewport;
EdgeInsets _cached = EdgeInsets.zero;

/// Flutter web may report zero view padding in a standalone Safari PWA even
/// while CSS exposes the home-indicator/notch area. Read on viewport changes,
/// not on every Matrix sync. This does not resize or scroll the browser viewport.
EdgeInsets browserSafeAreaInsets() {
  final viewport = (web.window.innerWidth, web.window.innerHeight);
  if (_viewport == viewport) return _cached;
  final body = web.document.body;
  if (body == null) return EdgeInsets.zero;
  final probe = _probe ??= web.document.createElement('div') as web.HTMLElement;
  if (!probe.isConnected) {
    probe.style.cssText =
        'position:fixed;visibility:hidden;pointer-events:none;'
        'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) '
        'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px);';
    body.appendChild(probe);
  }
  final style = web.window.getComputedStyle(probe);
  double pixels(String value) =>
      double.tryParse(value.replaceAll('px', '')) ?? 0;
  _viewport = viewport;
  return _cached = EdgeInsets.fromLTRB(
    pixels(style.paddingLeft),
    pixels(style.paddingTop),
    pixels(style.paddingRight),
    pixels(style.paddingBottom),
  );
}
