import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import '../services/browser_media.dart';

// Includes iOS Home Screen PWAs and desktop Safari, without changing native or
// Chromium rendering. WebKit's <img> decoder owns animated frame scheduling.
bool get prefersBrowserAnimation =>
    web.window.navigator.vendor.contains('Apple');

Widget browserAnimatedImage({
  required Uint8List bytes,
  required BoxFit fit,
  required double intrinsicWidth,
  required double intrinsicHeight,
  double? width,
  double? height,
}) => _BrowserAnimatedImage(
  bytes: bytes,
  fit: fit,
  intrinsicWidth: intrinsicWidth,
  intrinsicHeight: intrinsicHeight,
  width: width,
  height: height,
);

class _BrowserAnimatedImage extends StatefulWidget {
  const _BrowserAnimatedImage({
    required this.bytes,
    required this.fit,
    required this.intrinsicWidth,
    required this.intrinsicHeight,
    this.width,
    this.height,
  });
  final Uint8List bytes;
  final BoxFit fit;
  final double intrinsicWidth, intrinsicHeight;
  final double? width, height;
  @override
  State<_BrowserAnimatedImage> createState() => _BrowserAnimatedImageState();
}

class _BrowserAnimatedImageState extends State<_BrowserAnimatedImage> {
  Uri? _url;
  web.HTMLImageElement? _element;

  void _attach(web.HTMLImageElement element) {
    _element = element;
    _updateSource();
  }

  void _updateSource() {
    final old = _url;
    final gif =
        widget.bytes.length >= 3 &&
        widget.bytes[0] == 71 &&
        widget.bytes[1] == 73 &&
        widget.bytes[2] == 70;
    _url = createBrowserMediaUrl(
      widget.bytes,
      gif ? 'image/gif' : 'image/webp',
    );
    final element = _element!;
    element.alt = '';
    element.draggable = false;
    element.style
      ..width = '100%'
      ..height = '100%'
      ..display = 'block'
      ..pointerEvents = 'none'
      ..objectFit = _fit;
    element.src = _url.toString();
    if (old != null) releaseBrowserMediaUrl(old);
  }

  String get _fit => switch (widget.fit) {
    BoxFit.cover || BoxFit.fitWidth || BoxFit.fitHeight => 'cover',
    BoxFit.fill => 'fill',
    BoxFit.none => 'none',
    BoxFit.scaleDown => 'scale-down',
    BoxFit.contain => 'contain',
  };

  @override
  void didUpdateWidget(covariant _BrowserAnimatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_element == null) return;
    if (!identical(oldWidget.bytes, widget.bytes) &&
        !listEquals(oldWidget.bytes, widget.bytes)) {
      _updateSource();
    } else {
      _element!.style.objectFit = _fit;
    }
  }

  @override
  void dispose() {
    // Removing src stops WebKit's animation; revoke decrypted media on exit.
    _element?.removeAttribute('src');
    if (_url != null) releaseBrowserMediaUrl(_url!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.constrainSizeAndAttemptToPreserveAspectRatio(
        Size(
          widget.width ?? widget.intrinsicWidth,
          widget.height ?? widget.intrinsicHeight,
        ),
      );
      return SizedBox(
        width: size.width,
        height: size.height,
        child: HtmlElementView.fromTagName(
          tagName: 'img',
          onElementCreated: (element) =>
              _attach(element as web.HTMLImageElement),
        ),
      );
    },
  );
}
