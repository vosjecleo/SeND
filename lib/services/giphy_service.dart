import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GifSearchResult {
  const GifSearchResult({
    required this.title,
    required this.previewUrl,
    required this.shareUrl,
  });

  final String title;
  final Uri previewUrl;
  final Uri shareUrl;
}

/// Small client for GIPHY's public API (not adapted from a third-party picker).
/// The API key lives in the OS keyring, never Matrix account data or the repo.
/// See CREDITS.md for service attribution.
class GiphyService {
  GiphyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'deltiecord.giphy_api_key';
  final FlutterSecureStorage _storage;
  final HttpClient _http = HttpClient();

  Future<String?> readApiKey() => _storage.read(key: _keyName);

  Future<void> saveApiKey(String key) =>
      _storage.write(key: _keyName, value: key.trim());

  Future<List<GifSearchResult>> search(String query) async {
    final key = await readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('A Giphy API key is required.');
    }
    final uri = Uri.https('api.giphy.com', '/v1/gifs/search', {
      'api_key': key,
      'q': query,
      'limit': '24',
      'rating': 'pg-13',
      'lang': 'en',
    });
    final request = await _http.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Giphy returned ${response.statusCode}.');
    }
    final json = jsonDecode(body) as Map<String, Object?>;
    final data = json['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) {
          final images = item['images'] as Map?;
          final preview = images?['fixed_width'] as Map?;
          final original = images?['original'] as Map?;
          return GifSearchResult(
            title: item['title']?.toString() ?? 'GIF',
            previewUrl: Uri.parse(preview?['url']?.toString() ?? ''),
            shareUrl: Uri.parse(original?['url']?.toString() ?? ''),
          );
        })
        .where((gif) => gif.previewUrl.hasScheme && gif.shareUrl.hasScheme)
        .toList();
  }

  void dispose() => _http.close(force: true);
}
