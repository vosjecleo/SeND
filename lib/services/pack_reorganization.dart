import 'dart:typed_data';
import '../models/chat_models.dart';

/// Reference original media without downloading or re-encoding animations.
StickerDraftItem packItemReference(StickerSummary item) => StickerDraftItem(
  shortcode: item.name,
  bytes: Uint8List(0),
  mimeType: item.mimeType,
  width: item.width,
  height: item.height,
  assetType: item.assetType,
  reuse: item,
);

List<StickerDraftItem> mergePackItems(
  List<StickerDraftItem> existing,
  Iterable<StickerSummary> incoming,
) {
  final result = [...existing];
  final used = existing.map((item) => item.shortcode.toLowerCase()).toSet();
  for (final item in incoming) {
    if (result.length >= StickerPackDraft.maximumItems) {
      throw StateError(
        'A pack can contain at most ${StickerPackDraft.maximumItems} items. Split it first.',
      );
    }
    var base = item.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    base = base.replaceAll(RegExp(r'^[_-]+'), '');
    if (base.isEmpty) base = 'image';
    if (base.length > 90) base = base.substring(0, 90);
    var alias = base;
    for (var n = 2; used.contains(alias.toLowerCase()); n++) {
      alias = '${base}_$n';
    }
    used.add(alias.toLowerCase());
    result.add(
      StickerDraftItem(
        shortcode: alias,
        bytes: Uint8List(0),
        mimeType: item.mimeType,
        width: item.width,
        height: item.height,
        assetType: item.assetType,
        reuse: item,
      ),
    );
  }
  return result;
}

/// Reorganisation may reference only media in a currently accessible pack,
/// with its original dimensions and media type. No arbitrary MXC injection.
bool canReusePackItem(
  StickerDraftItem item,
  Iterable<StickerSummary> available,
) {
  final reference = item.reuse;
  return reference != null &&
      item.bytes.isEmpty &&
      available.any(
        (old) =>
            old.id == reference.id &&
            old.mxcUri == reference.mxcUri &&
            old.assetType == item.assetType &&
            old.mimeType == item.mimeType &&
            old.width == item.width &&
            old.height == item.height,
      );
}
