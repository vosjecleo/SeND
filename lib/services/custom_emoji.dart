import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:html/parser.dart' as html_parser;

import '../models/chat_models.dart';

const _editorEmojiHost = 'emoji.deltiecord.invalid';

enum CustomEmojiResizeFilter { bilinear, bicubic }

final class PreparedCustomEmoji {
  const PreparedCustomEmoji({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.resized,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final bool resized;
}

List<StickerDraftItem> applyCustomEmojiAliases(
  List<StickerDraftItem> items,
  List<String> aliases,
) {
  if (items.length != aliases.length) {
    throw StateError('Every custom emoji needs an alias.');
  }
  final trimmed = aliases.map((alias) => alias.trim()).toList(growable: false);
  if (trimmed.any(
    (alias) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$').hasMatch(alias),
  )) {
    throw StateError('Use 1–100 letters, numbers, underscores or hyphens.');
  }
  if (trimmed.map((alias) => alias.toLowerCase()).toSet().length !=
      trimmed.length) {
    throw StateError('Every emoji alias in a pack must be unique.');
  }
  return [
    for (var index = 0; index < items.length; index++)
      StickerDraftItem(
        shortcode: trimmed[index],
        bytes: items[index].bytes,
        mimeType: items[index].mimeType,
        width: items[index].width,
        height: items[index].height,
        assetType: StickerAssetType.emoji,
      ),
  ];
}

/// Prepares centred media without stretching or flattening animated sources.
///
/// The longest edge is reduced to 128 without changing the aspect ratio; the
/// other edge is centred on transparent pixels. Assets already within the
/// emoji limits are returned byte-for-byte so GIF/WebP animation is retained.
PreparedCustomEmoji prepareCustomEmojiAsset(
  Uint8List bytes,
  String mimeType, {
  required CustomEmojiResizeFilter filter,
  bool trimTransparentPadding = false,
  int targetDimension = StickerPackDraft.maximumEmojiDimension,
  int maximumBytes = StickerPackDraft.maximumEmojiBytes,
  bool forceResize = false,
}) {
  if (targetDimension < 16 ||
      targetDimension > 512 ||
      maximumBytes > 5 * 1024 * 1024) {
    throw StateError('Invalid image preparation limits.');
  }
  if (!const {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  }.contains(mimeType)) {
    throw StateError('Custom emoji must be PNG, JPEG, GIF or WebP.');
  }
  if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw StateError('Source emoji images must be at most 5 MiB.');
  }
  final decoder = image.findDecoderForData(bytes);
  final header = decoder?.startDecode(bytes);
  if (header == null ||
      header.width <= 0 ||
      header.height <= 0 ||
      header.width > 4096 ||
      header.height > 4096 ||
      header.width * header.height > 16 * 1024 * 1024) {
    throw StateError('Custom emoji has unsafe or unsupported dimensions.');
  }
  final withinLimits =
      header.width <= targetDimension &&
      header.height <= targetDimension &&
      bytes.length <= maximumBytes;
  if (withinLimits && !trimTransparentPadding && !forceResize) {
    return PreparedCustomEmoji(
      bytes: bytes,
      mimeType: mimeType,
      width: header.width,
      height: header.height,
      resized: false,
    );
  }

  if (header.numFrames > 240 ||
      header.width * header.height * header.numFrames > 24 * 1024 * 1024) {
    throw StateError(
      'This animation is too large to edit safely. Keep its original media or use a smaller source.',
    );
  }
  final decoded = image.decodeImage(bytes);
  if (decoded == null) throw StateError('Could not decode custom emoji.');
  if (decoded.numFrames > 1) {
    var left = 0,
        top = 0,
        right = decoded.width - 1,
        bottom = decoded.height - 1;
    if (trimTransparentPadding) {
      left = decoded.width;
      top = decoded.height;
      right = -1;
      bottom = -1;
      for (final frame in decoded.frames) {
        final bounds = _visibleAlphaBounds(frame);
        if (bounds == null) continue;
        left = min(left, bounds.left);
        top = min(top, bounds.top);
        right = max(right, bounds.right);
        bottom = max(bottom, bounds.bottom);
      }
      if (right < left) {
        throw StateError('The animation contains no visible pixels.');
      }
    }
    final cropped =
        left != 0 ||
        top != 0 ||
        right != decoded.width - 1 ||
        bottom != decoded.height - 1;
    if (withinLimits && !cropped && !forceResize) {
      return PreparedCustomEmoji(
        bytes: bytes,
        mimeType: mimeType,
        width: decoded.width,
        height: decoded.height,
        resized: false,
      );
    }
    final w = right - left + 1, h = bottom - top + 1;
    final scale = targetDimension / max(w, h);
    image.Image? animation;
    for (final frame in decoded.frames) {
      // Expand indexed GIF frames first; resizing a palette image otherwise
      // silently uses nearest-neighbour, ignoring the user's filter choice.
      final single = frame.convert(numChannels: 4, noAnimation: true);
      final croppedFrame = image.copyCrop(
        single,
        x: left,
        y: top,
        width: w,
        height: h,
      );
      final resized = image.copyResize(
        croppedFrame,
        width: max(1, (w * scale).round()),
        height: max(1, (h * scale).round()),
        interpolation: filter == CustomEmojiResizeFilter.bicubic
            ? image.Interpolation.cubic
            : image.Interpolation.linear,
      );
      final canvas = image.Image(
        width: targetDimension,
        height: targetDimension,
        numChannels: 4,
      )..frameDuration = max(10, frame.frameDuration);
      image.compositeImage(
        canvas,
        resized,
        dstX: (targetDimension - resized.width) ~/ 2,
        dstY: (targetDimension - resized.height) ~/ 2,
      );
      final indexed = _transparentGifFrame(canvas);
      if (animation == null) {
        animation = indexed..loopCount = decoded.loopCount;
      } else {
        animation.addFrame(indexed);
      }
    }
    final encoded = image.encodeGif(animation!);
    if (encoded.length > maximumBytes) {
      throw StateError(
        'The prepared animation exceeds the size limit. Try a smaller output size; it was not flattened.',
      );
    }
    return PreparedCustomEmoji(
      bytes: encoded,
      mimeType: 'image/gif',
      width: targetDimension,
      height: targetDimension,
      resized: true,
    );
  }
  var oriented = image.bakeOrientation(decoded);
  var trimmed = false;
  // Animations were handled above, including a shared crop across frames.
  if (trimTransparentPadding && header.numFrames == 1) {
    final bounds = _visibleAlphaBounds(oriented);
    if (bounds == null) {
      throw StateError('Custom emoji contains no visible pixels.');
    }
    if (bounds.left != 0 ||
        bounds.top != 0 ||
        bounds.right != oriented.width - 1 ||
        bounds.bottom != oriented.height - 1) {
      oriented = image.copyCrop(
        oriented,
        x: bounds.left,
        y: bounds.top,
        width: bounds.right - bounds.left + 1,
        height: bounds.bottom - bounds.top + 1,
      );
      trimmed = true;
    }
  }
  if (withinLimits && !trimmed && !forceResize) {
    return PreparedCustomEmoji(
      bytes: bytes,
      mimeType: mimeType,
      width: header.width,
      height: header.height,
      resized: false,
    );
  }
  final target = targetDimension;
  final scale = target / max(oriented.width, oriented.height);
  final resizedWidth = max(1, (oriented.width * scale).round());
  final resizedHeight = max(1, (oriented.height * scale).round());
  final resized = image.copyResize(
    oriented,
    width: resizedWidth,
    height: resizedHeight,
    interpolation: switch (filter) {
      CustomEmojiResizeFilter.bilinear => image.Interpolation.linear,
      CustomEmojiResizeFilter.bicubic => image.Interpolation.cubic,
    },
  );
  final canvas = image.Image(width: target, height: target, numChannels: 4);
  image.compositeImage(
    canvas,
    resized,
    dstX: (target - resizedWidth) ~/ 2,
    dstY: (target - resizedHeight) ~/ 2,
  );
  final encoded = Uint8List.fromList(image.encodePng(canvas, level: 6));
  if (encoded.length > maximumBytes) {
    throw StateError('Resized image still exceeds the size limit.');
  }
  return PreparedCustomEmoji(
    bytes: encoded,
    mimeType: 'image/png',
    width: target,
    height: target,
    resized: true,
  );
}

// The GIF encoder's automatic RGB quantizer drops alpha. Reserve one explicit
// transparent palette entry before encoding instead of creating black padding.
image.Image _transparentGifFrame(image.Image source) {
  final quantized = image.quantize(source, numberOfColors: 255);
  final colors = quantized.palette!;
  final palette = image.PaletteUint8(256, 4);
  for (var i = 0; i < colors.numColors && i < 255; i++) {
    palette.setRgba(
      i,
      colors.getRed(i),
      colors.getGreen(i),
      colors.getBlue(i),
      255,
    );
  }
  palette.setRgba(255, 0, 0, 0, 0);
  final result = image.Image(
    width: source.width,
    height: source.height,
    numChannels: 1,
    withPalette: true,
    palette: palette,
  )..frameDuration = source.frameDuration;
  for (final pixel in source) {
    result.setPixelIndex(
      pixel.x,
      pixel.y,
      pixel.a == 0 ? 255 : quantized.getPixel(pixel.x, pixel.y).index,
    );
  }
  return result;
}

({int left, int top, int right, int bottom})? _visibleAlphaBounds(
  image.Image source,
) {
  var left = source.width;
  var top = source.height;
  var right = -1;
  var bottom = -1;
  for (final pixel in source) {
    if (pixel.a <= 0) continue;
    left = min(left, pixel.x);
    top = min(top, pixel.y);
    right = max(right, pixel.x);
    bottom = max(bottom, pixel.y);
  }
  return right < 0
      ? null
      : (left: left, top: top, right: right, bottom: bottom);
}

StickerAssetType stickerAssetTypeFromImagePackItem(Map<String, Object?> item) {
  final explicit = item['net.deltiecord.asset_type'];
  final usage = (item['usage'] as List? ?? const []).whereType<String>();
  // Versions before custom emoji advertised both usages for every sticker.
  // Only an unambiguous standard usage or our explicit marker opts in.
  return explicit == 'emoji' ||
          (usage.contains('emoticon') && !usage.contains('sticker'))
      ? StickerAssetType.emoji
      : StickerAssetType.sticker;
}

({int width, int height}) validateCustomEmojiAsset(
  Uint8List bytes,
  String mimeType,
) {
  if (!const {
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
  }.contains(mimeType)) {
    throw StateError('Custom emoji must be PNG, JPEG, GIF or WebP.');
  }
  if (bytes.isEmpty || bytes.length > StickerPackDraft.maximumEmojiBytes) {
    throw StateError('Each custom emoji must be at most 256 KiB.');
  }
  // Header parsing obtains canvas bounds without allocating decoded pixels,
  // so a compressed image cannot trigger a large decode before rejection.
  final decoder = image.findDecoderForData(bytes);
  final dimensions = decoder?.startDecode(bytes);
  if (dimensions == null ||
      dimensions.width <= 0 ||
      dimensions.height <= 0 ||
      dimensions.width > StickerPackDraft.maximumEmojiDimension ||
      dimensions.height > StickerPackDraft.maximumEmojiDimension) {
    throw StateError('Custom emoji must be at most 128×128 pixels.');
  }
  return (width: dimensions.width, height: dimensions.height);
}

String customEmojiEditorLink(CustomEmojiReference emoji) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'id': emoji.id.toString(),
            'name': emoji.name,
            if (emoji.packId != null) 'pack': emoji.packId,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'https://$_editorEmojiHost/v1/$payload';
}

CustomEmojiReference? customEmojiFromEditorLink(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != _editorEmojiHost ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first != 'v1') {
    return null;
  }
  try {
    final payload = uri.pathSegments.last;
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final data = jsonDecode(utf8.decode(base64Url.decode(padded)));
    if (data is! Map) return null;
    final id = Uri.tryParse('${data['id'] ?? ''}');
    final name = '${data['name'] ?? ''}'.trim();
    if (id == null || !id.isScheme('mxc') || name.isEmpty) return null;
    return CustomEmojiReference(
      id: id,
      name: name,
      packId: data['pack'] as String?,
    );
  } catch (_) {
    return null;
  }
}

String customEmojiHtml(CustomEmojiReference emoji) =>
    '<img data-mx-emoticon height="32" '
    'src="${_escapeAttribute(emoji.id.toString())}" '
    'alt="${_escapeAttribute(emoji.fallback)}" '
    'title="${_escapeAttribute(emoji.fallback)}" '
    '${emoji.packId == null ? '' : 'data-deltiecord-emoji-pack="${_escapeAttribute(emoji.packId!)}" '}'
    'data-deltiecord-emoji-id="${_escapeAttribute(emoji.id.toString())}">';

String _escapeAttribute(String value) =>
    htmlEscape.convert(value).replaceAll('&#47;', '/');

/// Replaces editor-only custom-emoji links emitted by flutter_quill with the
/// Matrix custom-emoji `<img data-mx-emoticon>` representation.
String replaceCustomEmojiEditorLinks(String html) => html.replaceAllMapped(
  RegExp(
    r'<a\s+href="(https://emoji\.deltiecord\.invalid/v1/[A-Za-z0-9_-]+)"[^>]*>.*?</a>',
    caseSensitive: false,
  ),
  (match) {
    final emoji = customEmojiFromEditorLink(match.group(1));
    return emoji == null ? match.group(0)! : customEmojiHtml(emoji);
  },
);

({String plainText, String? html}) serializeCustomEmojiText(
  String source,
  List<CustomEmojiTextSpan> spans,
) {
  final leading = source.length - source.trimLeft().length;
  final trailing = source.trimRight().length;
  if (trailing <= leading) return (plainText: '', html: null);
  final text = source.substring(leading, trailing);
  final valid =
      spans
          .where(
            (span) =>
                span.start >= leading &&
                span.end <= trailing &&
                span.start < span.end &&
                source.substring(span.start, span.end) == span.emoji.fallback,
          )
          .toList(growable: false)
        ..sort((a, b) => a.start.compareTo(b.start));
  if (valid.isEmpty) return (plainText: text, html: null);
  final output = StringBuffer();
  var cursor = leading;
  for (final span in valid) {
    if (span.start < cursor) continue;
    output.write(_escapeMessageText(source.substring(cursor, span.start)));
    output.write(customEmojiHtml(span.emoji));
    cursor = span.end;
  }
  output.write(_escapeMessageText(source.substring(cursor, trailing)));
  return (plainText: text, html: output.toString());
}

List<CustomEmojiTextSpan> customEmojiSpansFromHtml(
  String? html,
  String fallback,
) {
  if (html == null || html.isEmpty || fallback.isEmpty) return const [];
  final document = html_parser.parseFragment(html);
  final spans = <CustomEmojiTextSpan>[];
  var cursor = 0;
  for (final element in document.querySelectorAll('img[data-mx-emoticon]')) {
    final id = Uri.tryParse(element.attributes['src'] ?? '');
    final token = element.attributes['alt'] ?? element.attributes['title'];
    if (id == null || !id.isScheme('mxc') || token == null || token.isEmpty) {
      continue;
    }
    final start = fallback.indexOf(token, cursor);
    if (start < 0) continue;
    final name = token.replaceAll(RegExp(r'^:|:$'), '');
    spans.add(
      CustomEmojiTextSpan(
        start: start,
        end: start + token.length,
        emoji: CustomEmojiReference(id: id, name: name),
      ),
    );
    cursor = start + token.length;
  }
  return spans;
}

String _escapeMessageText(String value) =>
    htmlEscape.convert(value).replaceAll('\n', '<br>');

/// Tracks custom-emoji spans through ordinary single-range text edits.
/// Editing any part of a fallback token intentionally converts it to text.
List<CustomEmojiTextSpan> reconcileCustomEmojiSpans(
  String before,
  String after,
  List<CustomEmojiTextSpan> spans,
) {
  if (before == after || spans.isEmpty) return List.of(spans);
  var prefix = 0;
  final shared = before.length < after.length ? before.length : after.length;
  while (prefix < shared &&
      before.codeUnitAt(prefix) == after.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < before.length - prefix &&
      suffix < after.length - prefix &&
      before.codeUnitAt(before.length - suffix - 1) ==
          after.codeUnitAt(after.length - suffix - 1)) {
    suffix++;
  }
  final oldEnd = before.length - suffix;
  final delta = after.length - before.length;
  return [
    for (final span in spans)
      if (oldEnd <= span.start)
        CustomEmojiTextSpan(
          start: span.start + delta,
          end: span.end + delta,
          emoji: span.emoji,
        )
      else if (prefix >= span.end)
        span,
  ];
}

List<dynamic> customEmojiDraftDelta(
  String text,
  List<CustomEmojiTextSpan> spans,
) {
  final ordered = List<CustomEmojiTextSpan>.of(spans)
    ..sort((a, b) => a.start.compareTo(b.start));
  final operations = <Map<String, Object?>>[];
  var cursor = 0;
  for (final span in ordered) {
    if (span.start < cursor || span.end > text.length) continue;
    if (span.start > cursor) {
      operations.add({'insert': text.substring(cursor, span.start)});
    }
    operations.add({
      'insert': text.substring(span.start, span.end),
      'attributes': {
        'deltiecord_emoji': {
          'id': span.emoji.id.toString(),
          'name': span.emoji.name,
          if (span.emoji.packId != null) 'pack': span.emoji.packId,
        },
      },
    });
    cursor = span.end;
  }
  if (cursor < text.length) operations.add({'insert': text.substring(cursor)});
  operations.add({'insert': '\n'});
  return operations;
}

({String text, List<CustomEmojiTextSpan> emojis}) customEmojiDraftFromDelta(
  List<dynamic> delta,
) {
  final text = StringBuffer();
  final spans = <CustomEmojiTextSpan>[];
  for (final raw in delta.whereType<Map>()) {
    final insert = raw['insert'];
    if (insert is! String) continue;
    final isFinalNewline = identical(raw, delta.last) && insert == '\n';
    if (isFinalNewline) continue;
    final start = text.length;
    text.write(insert);
    final metadata = (raw['attributes'] as Map?)?['deltiecord_emoji'];
    if (metadata is! Map) continue;
    final id = Uri.tryParse('${metadata['id'] ?? ''}');
    final name = '${metadata['name'] ?? ''}'.trim();
    if (id == null || !id.isScheme('mxc') || name.isEmpty) continue;
    spans.add(
      CustomEmojiTextSpan(
        start: start,
        end: start + insert.length,
        emoji: CustomEmojiReference(
          id: id,
          name: name,
          packId: metadata['pack'] as String?,
        ),
      ),
    );
  }
  return (text: text.toString(), emojis: spans);
}
