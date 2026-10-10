import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:deltiecord/ui/json_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('avatar frames stay bounded through repeated lifecycle changes', (
    tester,
  ) async {
    final first = img.Image(width: 64, height: 64);
    img.fill(first, color: img.ColorRgb8(255, 0, 0));
    first.frameDuration = 20;
    final second = img.Image(width: 64, height: 64);
    img.fill(second, color: img.ColorRgb8(0, 0, 255));
    second.frameDuration = 20;
    first.addFrame(second);
    final bytes = Uint8List.fromList(img.encodeGif(first));
    final live = HashSet<ui.Image>.identity();
    final oldCreate = ui.Image.onCreate;
    final oldDispose = ui.Image.onDispose;
    var created = 0;
    var peak = 0;
    ui.Image.onCreate = (image) {
      live.add(image);
      created++;
      if (live.length > peak) peak = live.length;
      oldCreate?.call(image);
    };
    ui.Image.onDispose = (image) {
      live.remove(image);
      oldDispose?.call(image);
    };
    addTearDown(() {
      ui.Image.onCreate = oldCreate;
      ui.Image.onDispose = oldDispose;
    });
    final playing = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: playing,
          builder: (context, autoplay, _) => Row(
            children: [
              for (var i = 0; i < 8; i++)
                ThemeAvatar(
                  backgroundImage: MemoryImage(bytes),
                  autoplay: autoplay,
                ),
            ],
          ),
        ),
      ),
    );
    for (var tick = 0; tick < 1200; tick++) {
      if (tick % 30 == 0) playing.value = !playing.value;
      if (tick % 100 == 0) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        live.length,
        lessThanOrEqualTo(32),
        reason: 'Unbounded frame handles at tick $tick',
      );
      expect(tester.takeException(), isNull);
    }
    expect(created, greaterThan(1000));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(live, isEmpty, reason: 'Image handles left after unmount');
    playing.dispose();
    // Printed for the investigation log, not application output.
    debugPrint(
      'Avatar stress: $created handles created, peak $peak, '
      '${live.length} remaining',
    );
  });
}
