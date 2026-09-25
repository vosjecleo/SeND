import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/custom_emoji.dart';
import 'package:deltiecord/ui/advanced_chat_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'widget_test.dart' show FakeBackend;

Uint8List animation({int width = 200, int height = 100}) {
  final first = image.Image(width: width, height: height, numChannels: 4)
    ..frameDuration = 120
    ..loopCount = 0;
  image.fill(first, color: image.ColorRgba8(255, 0, 0, 255));
  final second = image.Image(width: width, height: height, numChannels: 4)
    ..frameDuration = 240;
  image.fill(second, color: image.ColorRgba8(0, 0, 255, 255));
  first.addFrame(second);
  return Uint8List.fromList(image.encodeGif(first));
}

class PackBackend extends FakeBackend {
  StickerPackDraft? saved;
  bool fail = false;
  @override
  Future<void> replaceStickerPack(
    StickerPackSummary existing,
    StickerPackDraft replacement,
  ) async {
    if (fail) throw StateError('Network failed');
    saved = replacement;
  }
}

void main() {
  test('oversized animated emoji remains animated after resizing', () async {
    final prepared = prepareCustomEmojiAsset(
      animation(),
      'image/gif',
      filter: CustomEmojiResizeFilter.bicubic,
    );
    expect(prepared.mimeType, 'image/gif');
    expect((prepared.width, prepared.height), (128, 128));
    final decoded = image.decodeGif(prepared.bytes)!;
    expect(decoded.numFrames, 2);
    expect(decoded.frames.map((f) => f.frameDuration), [120, 240]);
    expect(decoded.loopCount, 0);
    final codec = await ui.instantiateImageCodec(prepared.bytes);
    expect(codec.frameCount, 2);
    final first = await codec.getNextFrame(),
        second = await codec.getNextFrame();
    expect(
      (await first.image.toByteData())!.buffer.asUint8List(),
      isNot((await second.image.toByteData())!.buffer.asUint8List()),
    );
    first.image.dispose();
    second.image.dispose();
    codec.dispose();
  });
  test(
    'unchanged animation remains byte identical; explicit edit preserves frames',
    () {
      final bytes = animation(width: 64, height: 32);
      final untouched = prepareCustomEmojiAsset(
        bytes,
        'image/gif',
        filter: CustomEmojiResizeFilter.bilinear,
      );
      expect(untouched.bytes, same(bytes));
      final edited = prepareCustomEmojiAsset(
        bytes,
        'image/gif',
        filter: CustomEmojiResizeFilter.bilinear,
        forceResize: true,
        targetDimension: 512,
        maximumBytes: 5 * 1024 * 1024,
      );
      expect(image.decodeGif(edited.bytes)!.numFrames, 2);
      expect(edited.width, 512);
    },
  );
  test('animated trim uses union of alpha bounds, preserving movement', () {
    image.Image frame(int left) {
      final palette = image.PaletteUint8(256, 4)
        ..setRgba(0, 0, 0, 0, 0)
        ..setRgba(1, 255, 0, 0, 255);
      final result = image.Image(
        width: 64,
        height: 64,
        numChannels: 1,
        withPalette: true,
        palette: palette,
      )..frameDuration = 100;
      for (var y = 20; y < 40; y++) {
        for (var x = left; x < left + 10; x++) {
          result.setPixelIndex(x, y, 1);
        }
      }
      return result;
    }

    final source = frame(10);
    final second = frame(40);
    source.addFrame(second);
    final prepared = prepareCustomEmojiAsset(
      Uint8List.fromList(image.encodeGif(source)),
      'image/gif',
      filter: CustomEmojiResizeFilter.bilinear,
      trimTransparentPadding: true,
    );
    final decoded = image.decodeGif(prepared.bytes)!;
    expect(decoded.numFrames, 2);
    expect(decoded.frames.first.getPixel(5, 64).a, greaterThan(0));
    expect(decoded.frames.last.getPixel(122, 64).a, greaterThan(0));
    expect(decoded.frames.first.getPixel(0, 0).a, 0);
    expect(decoded.frames.last.getPixel(5, 64).a, 0);
  });
  final pack = StickerPackSummary(
    id: 'pack',
    name: 'Cats',
    canManage: true,
    stickers: [
      for (final name in ['cat', 'dog'])
        StickerSummary(
          id: name,
          name: name,
          mxcUri: Uri.parse('mxc://example/$name'),
          mimeType: 'image/gif',
          assetType: StickerAssetType.emoji,
        ),
    ],
  );
  Future<void> open(WidgetTester tester, PackBackend backend) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 720,
                    height: 760,
                    child: StickerPackEditor(backend: backend, pack: pack),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'aliases/removal save unchanged media references without reimport',
    (tester) async {
      final backend = PackBackend();
      await open(tester, backend);
      await tester.enterText(find.byType(TextFormField).first, 'kitten');
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      await tester.tap(find.text('Remove selected'));
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(backend.saved!.stickers.single.shortcode, 'kitten');
      expect(backend.saved!.stickers.single.bytes, isEmpty);
      expect(
        backend.saved!.stickers.single.reuse!.mxcUri,
        pack.stickers.first.mxcUri,
      );
    },
  );
  testWidgets('bulk removal is undoable and duplicate aliases do not save', (
    tester,
  ) async {
    final backend = PackBackend();
    await open(tester, backend);
    await tester.tap(find.text('Select / clear all'));
    await tester.pump();
    await tester.tap(find.text('Remove selected'));
    await tester.pump();
    expect(find.byType(TextFormField), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).last, 'CAT');
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    expect(backend.saved, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow editor survives save failure without losing draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = PackBackend()..fail = true;
    await open(tester, backend);
    await tester.enterText(find.byType(TextFormField).first, 'kitten');
    // Simulate the smaller viewport left by a mobile keyboard.
    tester.view.physicalSize = const Size(390, 430);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Network failed'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.text('kitten'), findsOneWidget);
  });
}
