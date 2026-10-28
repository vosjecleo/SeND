import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/image_markup.dart';
import 'package:deltiecord/ui/attachment_image_editor.dart';
import 'package:deltiecord/ui/media_edit_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pixels = image.Image(width: 64, height: 32, numChannels: 4)
    ..clear(image.ColorRgba8(255, 255, 255, 255));
  final png = Uint8List.fromList(image.encodePng(pixels));
  test(
    'markup is exported into the cropped pixels, not just shown as an overlay',
    () async {
      final result = await renderMarkedImage(
        bytes: png,
        turns: 0,
        crop: [.5, 0, .5, 1],
        strokes: [
          {
            'color': 0xffff0000,
            'width': .15,
            'points': <List<double>>[
              [.1, .5],
              [.9, .5],
            ],
          },
        ],
      );
      final decoded = image.decodePng(result)!;
      expect((decoded.width, decoded.height), (32, 32));
      final pixel = decoded.getPixel(16, 16);
      expect(pixel.r, greaterThan(240));
      expect(pixel.g, lessThan(40));
    },
  );
  test('animated markup keeps frames, timing and correct rotation', () async {
    final encoder = image.PngEncoder()
      ..repeat = 3
      ..start(2);
    encoder.addFrame((pixels.clone()..frameDuration = 70));
    encoder.addFrame((pixels.clone()..frameDuration = 130));
    final original = encoder.finish()!;
    final result = await renderMarkedImage(
      bytes: original,
      turns: 1,
      crop: [0, 0, 1, 1],
      strokes: [],
    );
    final before = await ui.instantiateImageCodec(original),
        after = await ui.instantiateImageCodec(result);
    try {
      expect(after.frameCount, before.frameCount);
      expect(after.repetitionCount, before.repetitionCount);
      for (var i = 0; i < 2; i++) {
        final a = await before.getNextFrame(), b = await after.getNextFrame();
        expect((b.image.width, b.image.height), (32, 64));
        expect(b.duration, a.duration);
        a.image.dispose();
        b.image.dispose();
      }
    } finally {
      before.dispose();
      after.dispose();
    }
  });
  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'fullscreen markup works at ${width.toInt()} px with folded tools',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final draft = AttachmentDraft(
          bytes: png,
          name: 'a.png',
          mimeType: 'image/png',
          spoiler: false,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showAttachmentImageEditor(context, draft),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Edit image'), findsOneWidget);
        await tester.tap(find.text('Markup'));
        await tester.pumpAndSettle();
        expect(find.text('Marker'), findsOneWidget);
        await tester.drag(
          find.byKey(const ValueKey('media-editor-canvas')),
          const Offset(60, 12),
        );
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byTooltip('Undo stroke'));
        await tester.pump();
        expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.undo))
              .onPressed,
          isNull,
        );
        await tester.tap(find.text('Crop & rotate'));
        await tester.pumpAndSettle();
        expect(find.text('Marker'), findsNothing);
        expect(find.text('Lock aspect ratio'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Cancel edits'));
        await tester.pumpAndSettle();
        expect(find.text('Edit image'), findsNothing);
      },
    );
  }
  test('aspect locks use displayed pixel dimensions', () {
    final crop = cropForAspect(
      const Rect.fromLTWH(0, 0, 1, 1),
      const Size(400, 200),
      1,
    );
    expect(crop.width * 400, crop.height * 200);
    expect(rotateCrop(crop).width, crop.height);
  });
}
