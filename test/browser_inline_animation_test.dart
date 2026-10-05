@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:deltiecord/ui/lifecycle_memory_image.dart';

@JS('eval')
external JSAny? _evaluate(JSString source);

void main() {
  testWidgets('Apple browser advances real GIF pixels and resumes playback', (
    tester,
  ) async {
    // Exercise app Safari routing. Chromium is not a physical WebKit test.
    _evaluate(
      "Object.defineProperty(navigator, 'vendor', {configurable: true, value: 'Apple Computer, Inc.'})"
          .toJS,
    );
    addTearDown(() => _evaluate('delete navigator.vendor'.toJS));
    final first = img.Image(width: 8, height: 8)..frameDuration = 80;
    img.fill(first, color: img.ColorRgb8(255, 0, 0));
    final second = img.Image(width: 8, height: 8)..frameDuration = 80;
    img.fill(second, color: img.ColorRgb8(0, 0, 255));
    first.addFrame(second);
    final bytes = Uint8List.fromList(img.encodeGif(first));
    Widget view({bool autoplay = true}) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 80,
          height: 80,
          child: LifecycleMemoryImage(
            bytes: bytes,
            animated: true,
            autoplay: autoplay,
          ),
        ),
      ),
    );
    Future<Set<int>> pixels() async {
      final result = <int>{};
      for (var i = 0; i < 16; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 80));
        final images = tester.widgetList<RawImage>(find.byType(RawImage));
        for (final image in images) {
          if (image.image == null) continue;
          final data = await tester.runAsync(() => image.image!.toByteData());
          if (data != null) result.add(data.getUint32(0));
        }
      }
      return result;
    }

    await tester.pumpWidget(view());
    expect((await pixels()).length, 2);
    await tester.pumpWidget(view());
    expect((await pixels()).length, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect((await pixels()).length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect((await pixels()).length, 2);
    await tester.pumpWidget(view(autoplay: false));
    expect((await pixels()).length, 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
