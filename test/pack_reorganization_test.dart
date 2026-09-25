import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/pack_reorganization.dart';

StickerSummary sticker(String name) => StickerSummary(
  id: name,
  name: name,
  mxcUri: Uri.parse('mxc://example/$name'),
  mimeType: 'image/gif',
  width: 128,
  height: 128,
  assetType: StickerAssetType.emoji,
);

void main() {
  test(
    'merge preserves animations/media identity and resolves case-insensitive aliases',
    () {
      final original = [packItemReference(sticker('cat'))];
      final incoming = [sticker('CAT'), sticker('cat_2')];
      final merged = mergePackItems(original, incoming);
      expect(merged.map((e) => e.shortcode), ['cat', 'CAT_2', 'cat_2_2']);
      expect(original.length, 1);
      expect(merged[1].reuse, same(incoming.first));
      expect(
        merged.every((e) => e.bytes.isEmpty && e.mimeType == 'image/gif'),
        isTrue,
      );
    },
  );
  test('150 items allowed; 151 rejects without changing the original', () {
    final items = List.generate(
      149,
      (i) => packItemReference(sticker('item_$i')),
    );
    expect(mergePackItems(items, [sticker('extra')]).length, 150);
    expect(
      () => mergePackItems(items, [sticker('a'), sticker('b')]),
      throwsStateError,
    );
    expect(items.length, 149);
  });
  test(
    'reuse requires accessible original media and unchanged dimensions/type',
    () {
      final original = sticker('cat');
      final valid = packItemReference(original);
      expect(canReusePackItem(valid, [original]), isTrue);
      expect(canReusePackItem(valid, []), isFalse);
      final forged = StickerDraftItem(
        shortcode: 'cat',
        bytes: Uint8List(0),
        mimeType: 'image/gif',
        assetType: StickerAssetType.emoji,
        width: 1,
        height: 128,
        reuse: original,
      );
      expect(canReusePackItem(forged, [original]), isFalse);
    },
  );
}
