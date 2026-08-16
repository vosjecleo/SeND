import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class GifSearchResult {
  const GifSearchResult({
    required this.title,
    required this.previewUrl,
    required this.shareUrl,
  });

  final String title;
  final Uri previewUrl;
  final Uri shareUrl;

  Map<String, String> toJson() => {
    'title': title,
    'preview_url': previewUrl.toString(),
    'share_url': shareUrl.toString(),
  };

  static GifSearchResult? fromJson(Object? value) {
    if (value is! Map) return null;
    final previewUrl = Uri.tryParse(value['preview_url']?.toString() ?? '');
    final shareUrl = Uri.tryParse(value['share_url']?.toString() ?? '');
    if (previewUrl == null ||
        shareUrl == null ||
        !previewUrl.hasScheme ||
        !shareUrl.hasScheme) {
      return null;
    }
    return GifSearchResult(
      title: value['title']?.toString() ?? 'GIF',
      previewUrl: previewUrl,
      shareUrl: shareUrl,
    );
  }
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
  File? _favoritesFile;
  List<GifSearchResult>? _favorites;

  Future<List<GifSearchResult>> search(String query) => _request({'q': query});

  Future<List<GifSearchResult>> trending() async {
    try {
      return await _request(const {'mode': 'trending'});
    } on HttpException {
      // Older deployments of the proxy only expose search. Keep the picker
      // useful during a rolling server upgrade, albeit with approximate
      // trending results.
      return search('trending');
    }
  }

  Future<List<GifSearchResult>> _request(
    Map<String, String> queryParameters,
  ) async {
    final base = Uri.parse(_proxyUrl);
    if (base.scheme != 'https') {
      throw StateError('The GIF search proxy must use HTTPS.');
    }
    final uri = base.replace(queryParameters: queryParameters);
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

  Future<List<GifSearchResult>> favorites() async {
    final loaded = _favorites;
    if (loaded != null) return List.unmodifiable(loaded);
    try {
      final support = await getApplicationSupportDirectory();
      _favoritesFile = File(
        path.join(support.path, 'deltiecord', 'giphy_favorites.json'),
      );
      final file = _favoritesFile!;
      if (!await file.exists()) {
        _favorites = [];
      } else {
        final decoded = jsonDecode(await file.readAsString()) as List;
        _favorites = decoded
            .map(GifSearchResult.fromJson)
            .whereType<GifSearchResult>()
            .toList();
      }
    } catch (_) {
      _favorites = [];
    }
    return List.unmodifiable(_favorites!);
  }

  Future<bool> toggleFavorite(GifSearchResult gif) async {
    await favorites();
    final existing = _favorites!.indexWhere(
      (favorite) => favorite.shareUrl == gif.shareUrl,
    );
    final nowFavorite = existing < 0;
    if (nowFavorite) {
      _favorites!.insert(0, gif);
    } else {
      _favorites!.removeAt(existing);
    }
    final file = _favoritesFile;
    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(_favorites!.map((favorite) => favorite.toJson()).toList()),
        flush: true,
      );
    }
    return nowFavorite;
  }

  bool isFavorite(GifSearchResult gif) =>
      _favorites?.any((favorite) => favorite.shareUrl == gif.shareUrl) ?? false;

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
