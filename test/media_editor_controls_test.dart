import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/media_compression.dart';
import 'package:deltiecord/ui/attachment_image_editor.dart';
import 'package:deltiecord/ui/media_edit_canvas.dart';
import 'package:deltiecord/ui/media_editor_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  for (final width in [320.0, 400.0]) {
    testWidgets(
      'mobile editor uses spare space and keeps colours in one row at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final draft = AttachmentDraft(
          bytes: Uint8List.fromList(
            image.encodePng(image.Image(width: 80, height: 60)),
          ),
          name: 'test.png',
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
        expect(find.byType(DropdownButtonFormField<double>), findsOneWidget);
        final cropHeight = tester
            .getSize(find.byKey(const ValueKey('editor-preview-region')))
            .height;
        final totalHeight = tester
            .getSize(find.byType(MediaEditorLayout))
            .height;
        expect(cropHeight, greaterThan(totalHeight * .55));
        await tester.tap(find.byTooltip('Quality'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('editor-preview-region')))
              .height,
          cropHeight,
        );
        await tester.tap(find.byTooltip('Markup'));
        await tester.pumpAndSettle();
        expect(
          tester
              .getSize(find.byKey(const ValueKey('editor-preview-region')))
              .height,
          cropHeight,
        );
        final ys =
            ['Red', 'Yellow', 'Green', 'Blue', 'Purple', 'White', 'Black']
                .map((name) => tester.getCenter(find.byTooltip('$name ink')).dy)
                .toList();
        expect(ys.every((y) => (y - ys.first).abs() < 1), true);
        final selected = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.edit_outlined),
        );
        expect(selected.color, Colors.white);
        expect((selected.icon as Icon).weight, 700);
        expect(find.textContaining('Draw directly'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [400.0, 1200.0]) {
    testWidgets(
      'quality follows preferences and spoiler survives export at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        AttachmentDraft? saved;
        final draft = AttachmentDraft(
          bytes: Uint8List.fromList(
            image.encodePng(image.Image(width: 80, height: 60)),
          ),
          name: 'test.png',
          mimeType: 'image/png',
          spoiler: false,
          caption: 'keep caption',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await showAttachmentImageEditor(
                      context,
                      draft,
                      preferences: const AppPreferences(
                        imageCompression: ImageCompressionPreset.smaller,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(ExpansionTile), findsNothing);
        if (width < 850) {
          await tester.tap(find.byTooltip('Quality'));
          await tester.pumpAndSettle();
        } else {
          await tester.ensureVisible(
            find.widgetWithText(ChoiceChip, 'Smaller'),
          );
        }
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Smaller'))
              .selected,
          true,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Original').last);
        await tester.pump();
        await tester.ensureVisible(find.byTooltip('Mark as spoiler'));
        await tester.tap(find.byTooltip('Mark as spoiler'));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('editor-spoiler-haze')),
          findsOneWidget,
        );
        await tester.tap(find.text('Use image'));
        await tester.pumpAndSettle();
        expect(saved?.spoiler, true);
        expect(saved?.caption, 'keep caption');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('crop corners accept drags outside the image boundary', (
    tester,
  ) async {
    Rect crop = const Rect.fromLTWH(0, 0, 1, 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 300,
            child: StatefulBuilder(
              builder: (context, update) => MediaEditCanvas(
                sourceSize: const Size(200, 200),
                turns: 0,
                crop: crop,
                cropMode: true,
                locked: false,
                onCrop: (value) => update(() => crop = value),
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(
      find.byKey(const ValueKey('media-editor-canvas')),
    );
    await tester.dragFrom(
      bounds.topLeft + const Offset(8, 8),
      const Offset(60, 60),
    );
    await tester.pump();
    expect(crop.left, greaterThan(.1));
    expect(crop.top, greaterThan(.1));
  });
}
