import 'dart:typed_data';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final a = Uri.parse('https://example.org/a');
  final b = Uri.parse('https://example.org/b');
  LinkPreview preview(Uri uri, int size) =>
      LinkPreview(url: uri, imageBytes: Uint8List(size));
  test(
    'preview cache enforces a byte budget, including replacement and clear',
    () {
      final cache = LinkPreviewCache(maximumImageBytes: 100);
      cache.put(a, preview(a, 60));
      cache.put(b, preview(b, 60));
      expect(cache.contains(a), false);
      expect(cache.contains(b), true);
      expect(cache.cachedImageBytes, 60);
      cache.put(b, preview(b, 20));
      expect(cache.cachedImageBytes, 20);
      cache.put(a, preview(a, 101));
      expect(cache.cachedImageBytes, lessThanOrEqualTo(100));
      expect(cache.contains(a), false);
      cache.clear();
      expect(cache.cachedImageBytes, 0);
    },
  );
  test(
    'expired images release budget and failed previews cost no image bytes',
    () {
      final cache = LinkPreviewCache(
        successLifetime: const Duration(seconds: -1),
      );
      cache.put(a, preview(a, 60));
      expect(cache.get(a), isNull);
      expect(cache.cachedImageBytes, 0);
      cache.put(b, null);
      expect(cache.contains(b), true);
      expect(cache.cachedImageBytes, 0);
    },
  );
}
