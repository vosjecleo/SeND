import 'dart:typed_data';
import 'package:deltiecord/ui/archive_navigation.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/lifecycle_memory_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'support/fake_backend.dart';

void main() {
  for (final indexed in [false, true]) {
    testWidgets(
      'Archive reveal keeps GIF decoder and visible frame, indexed=$indexed',
      (tester) async {
        final frame = img.Image(width: 16, height: 16);
        img.fill(frame, color: img.ColorRgb8(255, 0, 0));
        frame.frameDuration = 40;
        final second = img.Image(width: 16, height: 16);
        img.fill(second, color: img.ColorRgb8(0, 0, 255));
        second.frameDuration = 40;
        frame.addFrame(second);
        final bytes = Uint8List.fromList(img.encodeGif(frame));
        final backend = FakeBackend();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ArchivePullList(
                backend: backend,
                itemCount: 20,
                findChildIndexCallback: !indexed
                    ? null
                    : (key) =>
                          key is ValueKey<String> &&
                              key.value.startsWith('row-')
                          ? int.tryParse(key.value.substring(4))
                          : null,
                itemBuilder: (_, index) => SizedBox(
                  key: ValueKey('row-$index'),
                  height: 56,
                  child: index == 0
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: ThemeAvatar(
                            backgroundImage: MemoryImage(bytes),
                            autoplay: true,
                          ),
                        )
                      : Text('Room $index'),
                ),
              ),
            ),
          ),
        );
        final decoder = find.descendant(
          of: find.byKey(const ValueKey('row-0')),
          matching: find.byType(LifecycleMemoryImage),
        );
        final image = find.descendant(
          of: decoder,
          matching: find.byType(RawImage),
        );
        for (
          var attempt = 0;
          attempt < 20 && tester.widget<RawImage>(image).image == null;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(tester.widget<RawImage>(image).image, isNotNull);
        final state = tester.state(decoder);
        Future<void> checkFrame() async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.state(decoder), same(state));
          expect(tester.widget<RawImage>(image).image, isNotNull);
          expect(tester.takeException(), isNull);
        }

        for (var repeat = 0; repeat < 2; repeat++) {
          final gesture = await tester.startGesture(
            tester.getTopLeft(find.byType(ListView)) + const Offset(200, 50),
          );
          for (var step = 0; step < 30; step++) {
            await gesture.moveBy(const Offset(0, 8));
            await checkFrame();
          }
          await gesture.up();
          for (var step = 0; step < 40; step++) {
            await checkFrame();
          }
          expect(
            find.byKey(const ValueKey('home-archive-entry')),
            findsOneWidget,
          );
          tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(56);
          await checkFrame();
          await checkFrame();
          expect(
            find.byKey(const ValueKey('home-archive-entry')),
            findsNothing,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
        backend.dispose();
      },
    );
  }
}
