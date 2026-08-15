import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
/// Deltiecord's rate-limited server proxy adds the shared application key, so
/// neither source archives nor release binaries contain that credential.
class GiphyService {
  GiphyService();

  static const _proxyUrl = String.fromEnvironment(
    'GIPHY_PROXY_URL',
    defaultValue: 'https://deltie.net/api/servers/giphy/search',
  );
  final HttpClient _http = HttpClient();

  Future<List<GifSearchResult>> search(String query) async {
    final base = Uri.parse(_proxyUrl);
    if (base.scheme != 'https') {
      throw StateError('The GIF search proxy must use HTTPS.');
    }
    final uri = base.replace(queryParameters: {'q': query});
    final request = await _http.getUrl(uri);
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('GIF search returned ${response.statusCode}.');
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

  Future<Uint8List> download(GifSearchResult gif) async {
    final uri = gif.shareUrl;
    if (uri.scheme != 'https' ||
        !(uri.host == 'giphy.com' || uri.host.endsWith('.giphy.com'))) {
      throw StateError('GIPHY returned an unexpected media URL.');
    }
    final request = await _http.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('GIPHY media returned ${response.statusCode}.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  void dispose() => _http.close(force: true);
}
