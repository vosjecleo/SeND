import 'dart:typed_data';

import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('visible unfocused web views keep playing; hidden views stop', () {
    expect(
      imageLifecycleVisible(AppLifecycleState.inactive, browser: true),
      isTrue,
    );
    expect(
      imageLifecycleVisible(AppLifecycleState.inactive, browser: false),
      isFalse,
    );
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(imageLifecycleVisible(state, browser: true), isFalse);
    }
  });
  test('WebP animation is detected without MIME metadata', () {
    final header = Uint8List(30);
    header.setRange(0, 4, 'RIFF'.codeUnits);
    header.setRange(8, 12, 'WEBP'.codeUnits);
    header.setRange(12, 16, 'VP8X'.codeUnits);
    header[20] = 2;
    expect(hasAnimatedImageHeader(header), isTrue);
    header[20] = 0;
    expect(hasAnimatedImageHeader(header), isFalse);
    expect(hasAnimatedImageHeader(Uint8List(3)), isFalse);
  });
  Uint8List animatedFixture() {
    final first = img.Image(width: 4, height: 4);
    img.fill(first, color: img.ColorRgb8(255, 0, 0));
    first.frameDuration = 80;
    final second = img.Image(width: 4, height: 4);
    img.fill(second, color: img.ColorRgb8(0, 0, 255));
    second.frameDuration = 80;
    first.addFrame(second);
    return Uint8List.fromList(img.encodeGif(first));
  }

  Future<Set<Object>> observeFrames(WidgetTester tester) async {
    final frames = <Object>{};
    for (var i = 0; i < 16; i++) {
      // Codec futures run outside fake time. Let the engine deliver a frame
      // before advancing the framework animation clock.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      for (final raw in tester.widgetList<RawImage>(find.byType(RawImage))) {
        if (raw.image != null) frames.add(raw.image!);
      }
    }
    return frames;
  }

  testWidgets('GIF advances despite inherited UI pause and after resume', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: TickerMode(
            enabled: false,
            child: LifecycleMemoryImage(
              bytes: animatedFixture(),
              animated: true,
              autoplay: true,
            ),
          ),
        ),
      ),
    );
    expect((await observeFrames(tester)).length, greaterThan(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect((await observeFrames(tester)).length, greaterThan(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('autoplay off retains a single frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LifecycleMemoryImage(
          bytes: animatedFixture(),
          animated: true,
          autoplay: false,
        ),
      ),
    );
    expect((await observeFrames(tester)).length, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('only GIF-like preview providers request looping playback', () {
    expect(
      shouldLoopLinkPreview(
        Uri.parse('https://media.giphy.com/media/x/giphy.mp4'),
      ),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://tenor.com/view/example')),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://example.org/animation.gif')),
      isTrue,
    );
    expect(
      shouldLoopLinkPreview(Uri.parse('https://example.org/video.mp4')),
      isFalse,
    );
  });
}
