import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Compare the production clip with two proposed isolation strategies. The
// outer capture boundary is test instrumentation, not an avatar boundary.
void main() {
  for (final size in [34.0, 124.0]) {
    for (final mode in [
      'current',
      'boundary',
      'offscreen',
      'unclipped control',
    ]) {
      testWidgets('$size avatar: $mode pixel containment', (tester) async {
        final first = img.Image(width: 64, height: 64);
        img.fill(first, color: img.ColorRgb8(255, 0, 0));
        first.frameDuration = 40;
        final second = img.Image(width: 64, height: 64);
        img.fill(second, color: img.ColorRgb8(0, 0, 255));
        second.frameDuration = 40;
        first.addFrame(second);
        final bytes = Uint8List.fromList(img.encodeGif(first));
        final capture = GlobalKey();
        final state = ValueNotifier<int>(0);
        final seen = <int>{};
        var escapedPixels = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: capture,
                child: ValueListenableBuilder<int>(
                  valueListenable: state,
                  builder: (context, tick, _) {
                    Widget avatar = ThemeAvatarClip(
                      clipBehavior: mode == 'unclipped control'
                          ? Clip.none
                          : mode == 'offscreen'
                          ? Clip.antiAliasWithSaveLayer
                          : Clip.antiAlias,
                      child: LifecycleMemoryImage(
                        bytes: bytes,
                        animated: true,
                        autoplay: tick % 9 != 0,
                        fit: BoxFit.cover,
                      ),
                    );
                    if (mode == 'boundary') {
                      avatar = RepaintBoundary(child: avatar);
                    }
                    return ColoredBox(
                      color: tick.isEven ? Colors.green : Colors.yellow,
                      child: SizedBox.square(
                        dimension: size + 16,
                        child: Stack(
                          children: [
                            Positioned(
                              left: 8,
                              top: 8,
                              width: size,
                              height: size,
                              child: avatar,
                            ),
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                width: 8,
                                height: 8,
                                color: tick.isEven
                                    ? Colors.white
                                    : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        for (var frame = 0; frame < 36; frame++) {
          if (frame % 3 == 0) state.value++;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 12)),
          );
          await tester.pump(const Duration(milliseconds: 40));
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await tester.runAsync(() => boundary.toImage());
          final data = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
          );
          final width = image!.width;
          final center = (8 + size / 2).floor();
          final offset = (center * width + center) * 4;
          if (data!.getUint8(offset) == 255 && data.getUint8(offset + 1) == 0) {
            seen.add(0);
          }
          if (data.getUint8(offset + 2) == 255) seen.add(1);
          for (var y = 8; y < 8 + size; y++) {
            for (var x = 8; x < 8 + size; x++) {
              final dx = x + .5 - (8 + size / 2);
              final dy = y + .5 - (8 + size / 2);
              if (dx * dx + dy * dy <= (size / 2 + 2) * (size / 2 + 2)) {
                continue; // Exclude the antialiased edge.
              }
              final i = (y * width + x) * 4;
              final r = data.getUint8(i);
              final g = data.getUint8(i + 1);
              final b = data.getUint8(i + 2);
              if ((r > 100 && g < 30 && b < 30) ||
                  (b > 100 && r < 30 && g < 30)) {
                escapedPixels++;
              }
            }
          }
          image.dispose();
          expect(tester.takeException(), isNull);
        }
        expect(seen, {0, 1}, reason: 'Both animation colours must be rendered');
        expect(escapedPixels, mode == 'unclipped control' ? greaterThan(0) : 0);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      });
    }
  }
}
