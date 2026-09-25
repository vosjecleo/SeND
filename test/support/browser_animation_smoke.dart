// Browser-only implementation, selected by browser_animation_test.dart.
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:web/web.dart' as web;
import 'package:deltiecord/ui/browser_animated_image_web.dart';

// Flutter widget tests mock platform-view transport, so create real DOM images
// behind a test registry. Decoding, Blob URLs and fetch still use the browser.
class ImageRegistry implements ui_web.PlatformViewRegistry {
  final elements = <int, web.HTMLElement>{};
  @override
  Object getViewById(int id) => elements[id]!;
  @override
  bool registerViewFactory(
    String viewType,
    Function viewFactory, {
    bool isVisible = true,
  }) => false;
  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'create') {
      final args = call.arguments as Map;
      final params = args['params'] as Map?;
      elements[args['id'] as int] =
          web.document.createElement('${params?['tagName'] ?? 'div'}')
              as web.HTMLElement;
    } else if (call.method == 'dispose') {
      elements.remove(call.arguments as int)?.remove();
    }
    return null;
  }
}

void main() {
  testWidgets(
    'browser-native GIF retains animation bytes across rebuilds and detaches',
    (tester) async {
      final registry = ImageRegistry();
      ui_web.debugOverridePlatformViewRegistry(registry);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        registry.handle,
      );
      addTearDown(() {
        ui_web.debugOverridePlatformViewRegistry(null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        );
      });
      final first = img.Image(width: 8, height: 8)..frameDuration = 120;
      img.fill(first, color: img.ColorRgb8(255, 0, 0));
      final second = img.Image(width: 8, height: 8)..frameDuration = 120;
      img.fill(second, color: img.ColorRgb8(0, 0, 255));
      first.addFrame(second);
      final bytes = Uint8List.fromList(img.encodeGif(first));
      Widget view(Uint8List data) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 80,
            height: 80,
            child: browserAnimatedImage(
              bytes: data,
              fit: BoxFit.contain,
              intrinsicWidth: 8,
              intrinsicHeight: 8,
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(bytes));
      web.HTMLImageElement? element;
      for (var i = 0; i < 18; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 90)),
        );
        await tester.pump();
        final surfaces = tester.widgetList<PlatformViewSurface>(
          find.byType(PlatformViewSurface),
        );
        if (surfaces.isNotEmpty) {
          element =
              ui_web.platformViewRegistry.getViewById(
                    surfaces.first.controller.viewId,
                  )
                  as web.HTMLImageElement;
        }
        if (element != null && element.complete && element.naturalWidth > 0) {
          break;
        }
      }
      expect(element, isNotNull);
      expect(element!.naturalWidth, 8);
      // Canvas drawImage samples the default GIF frame, not its visible frame.
      // Verify the browser received the complete multi-frame source instead.
      final buffer = await tester.runAsync(() async {
        final response = await web.window.fetch(element!.src.toJS).toDart;
        return (await response.arrayBuffer().toDart).toDart.asUint8List();
      });
      expect(buffer, bytes);
      expect(img.decodeGif(buffer!)!.numFrames, 2);
      final src = element.src;
      await tester.pumpWidget(view(Uint8List.fromList(bytes)));
      await tester.pump();
      expect(element.src, src);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(element.hasAttribute('src'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
