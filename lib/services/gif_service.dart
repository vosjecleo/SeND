import 'dart:convert';
import 'platform_io.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../version.dart';
import 'bounded_http.dart';
import 'public_network_address.dart';
import 'private_file_store.dart';
import 'browser_private_store.dart';

class GifSearchResult {
  const GifSearchResult({
    required this.title,
    required this.previewUrl,
    required this.shareUrl,
  });

  final String title;
  final Uri previewUrl;
  final Uri shareUrl;

  static GifSearchResult? fromKlipy(Map item) {
    if (item['type'] != 'gif') return null;
    final file = item['file'];
    if (file is! Map) return null;
    Uri? rendition(List<String> sizes) {
      for (final size in sizes) {
        final formats = file[size];
        final gif = formats is Map ? formats['gif'] : null;
        if (gif is! Map) continue;
        final uri = Uri.tryParse('${gif['url']}');
        if (uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'static.klipy.com' &&
            uri.userInfo.isEmpty &&
            (!uri.hasPort || uri.port == 443) &&
            (gif['size'] is! num || (gif['size'] as num) <= 25 * 1024 * 1024)) {
          return uri;
        }
      }
      return null;
    }

    final preview = rendition(const ['sm', 'xs', 'md', 'hd']);
    final media = rendition(const ['md', 'hd', 'sm', 'xs']);
    if (preview == null || media == null) return null;
    return GifSearchResult(
      title: item['title']?.toString() ?? 'GIF',
      previewUrl: preview,
      shareUrl: media,
    );
  }

  // Older saved favourites point at GIPHY's *_s.gif still rendition.
  Uri get animatedPreviewUrl =>
      previewUrl.path.endsWith('_s.gif') ? shareUrl : previewUrl;

  static GifSearchResult? fromApi(Map item) {
    final images = item['images'] as Map?;
    final preview =
        (images?['fixed_width'] as Map?) ??
        (images?['downsized'] as Map?) ??
        (images?['original'] as Map?);
    // Keep uploads bounded without deliberately selecting a still rendition.
    final send =
        (images?['downsized_medium'] as Map?) ??
        (images?['downsized'] as Map?) ??
        (images?['original'] as Map?);
    final previewUrl = Uri.tryParse(preview?['url']?.toString() ?? '');
    final shareUrl = Uri.tryParse(send?['url']?.toString() ?? '');
    if (previewUrl == null ||
        shareUrl == null ||
        !previewUrl.hasScheme ||
        !shareUrl.hasScheme) {
      return null;
    }
    return GifSearchResult(
      title: item['title']?.toString() ?? 'GIF',
      previewUrl: previewUrl,
      shareUrl: shareUrl,
    );
  }

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

/// Provider-neutral picker/storage client. The proxy selects the provider;
/// provider-specific response parsing stays at this boundary.
/// Deltiecord's rate-limited server proxy adds the shared application key, so
/// neither source archives nor release binaries contain that credential.
class GifService {
  GifService();

  static const _proxyUrl = String.fromEnvironment(
    'GIF_PROXY_URL',
    defaultValue: 'https://deltie.net/api/servers/klipy/search',
  );
  static const _maximumSearchBytes = 2 * 1024 * 1024;
  static const _maximumGifBytes = 25 * 1024 * 1024;
  static const _requestTimeout = Duration(seconds: 10);
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 10)
    ..userAgent = 'Deltiecord/$deltiecordVersion';
  File? _favoritesFile;
  static List<GifSearchResult>? _favorites;
  static final _mediaCache = <Uri, Uint8List>{};
  static final _mediaRequests = <Uri, Future<Uint8List>>{};
  static int _cachedBytes = 0;

  Future<List<GifSearchResult>> search(String query) => _request({'q': query});

  Future<GifSearchResult?> resolveKlipyLink(Uri uri) async {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    if (uri.host == 'static.klipy.com' && uri.path.endsWith('.gif')) {
      return GifSearchResult(
        title: 'KLIPY GIF',
        previewUrl: uri,
        shareUrl: uri,
      );
    }
    if (uri.host != 'klipy.com' ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first != 'gifs' ||
        !RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(uri.pathSegments.last)) {
      return null;
    }
    final result = await _request({'slug': uri.pathSegments.last});
    return result.isEmpty ? null : result.first;
  }

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
    final base = kIsWeb
        ? Uri.base.resolve('/api/servers/klipy/search')
        : Uri.parse(_proxyUrl);
    if (base.scheme != 'https') {
      throw StateError('The GIF search proxy must use HTTPS.');
    }
    final uri = base.replace(queryParameters: queryParameters);
    final request = await _http.getUrl(uri).timeout(_requestTimeout);
    request
      ..followRedirects = false
      ..headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('GIF search returned ${response.statusCode}.');
    }
    if (!hasContentType(response, const ['application/json'])) {
      await response.drain<void>();
      throw const HttpException('GIF search returned an unexpected response.');
    }
    if (response.contentLength > _maximumSearchBytes) {
      await response.drain<void>();
      throw const HttpException('GIF search response is too large.');
    }
    final body = utf8.decode(
      await readBoundedResponse(
        response,
        maximumBytes: _maximumSearchBytes,
        inactivityTimeout: _requestTimeout,
      ),
    );
    final json = jsonDecode(body) as Map<String, Object?>;
    final payload = json['data'];
    final data = payload is Map ? payload['data'] : payload;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map(GifSearchResult.fromKlipy)
        .whereType<GifSearchResult>()
        .toList();
  }

  Future<List<GifSearchResult>> favorites() async {
    final loaded = _favorites;
    if (loaded != null) return List.unmodifiable(loaded);
    try {
      if (!kIsWeb) {
        final support = await getApplicationSupportDirectory();
        // Preserve the old filename so upgrades retain GIPHY favourites.
        _favoritesFile = File(
          path.join(support.path, 'deltiecord', 'giphy_favorites.json'),
        );
      }
      final file = _favoritesFile;
      final text = kIsWeb
          ? await BrowserPrivateStore.read('gifs')
          : await file!.exists()
          ? await file.readAsString()
          : null;
      if (text == null) {
        _favorites = [];
      } else {
        final decoded = jsonDecode(text) as List;
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
    if (!kIsWeb && _favoritesFile == null) {
      final support = await getApplicationSupportDirectory();
      _favoritesFile = File(
        path.join(support.path, 'deltiecord', 'giphy_favorites.json'),
      );
    }
    final existing = _favorites!.indexWhere(
      (favorite) => favorite.shareUrl == gif.shareUrl,
    );
    final nowFavorite = existing < 0;
    if (nowFavorite) {
      _favorites!.insert(0, gif);
      if (_favorites!.length > 100) _favorites!.removeLast();
    } else {
      _favorites!.removeAt(existing);
    }
    final file = _favoritesFile;
    if (kIsWeb) {
      await BrowserPrivateStore.write(
        'gifs',
        jsonEncode(_favorites!.map((gif) => gif.toJson()).toList()),
      );
    }
    if (file != null) {
      await writePrivateTextFile(
        file,
        jsonEncode(_favorites!.map((favorite) => favorite.toJson()).toList()),
      );
    }
    return nowFavorite;
  }

  bool isFavorite(GifSearchResult gif) =>
      _favorites?.any((favorite) => favorite.shareUrl == gif.shareUrl) ?? false;

  Future<Uint8List> download(GifSearchResult gif) async {
    final uri = gif.shareUrl;
    final cached = _mediaCache.remove(uri);
    if (cached != null) {
      _mediaCache[uri] = cached;
      return cached;
    }
    final existing = _mediaRequests[uri];
    if (existing != null) return existing;
    final request = _downloadMedia(uri);
    _mediaRequests[uri] = request;
    try {
      final bytes = await request;
      if (bytes.length <= 8 * 1024 * 1024) {
        _mediaCache[uri] = bytes;
        _cachedBytes += bytes.length;
        while (_mediaCache.length > 32 || _cachedBytes > 32 * 1024 * 1024) {
          _cachedBytes -= _mediaCache.remove(_mediaCache.keys.first)!.length;
        }
      }
      return bytes;
    } finally {
      _mediaRequests.remove(uri);
    }
  }

  Future<Uint8List> preview(GifSearchResult gif) => download(
    GifSearchResult(
      title: gif.title,
      previewUrl: gif.animatedPreviewUrl,
      shareUrl: gif.animatedPreviewUrl,
    ),
  );

  Future<Uint8List> _downloadMedia(Uri uri) async {
    if (!_isGiphyMediaUri(uri)) {
      throw StateError('The GIF provider returned an unexpected media URL.');
    }
    final response = await _openGiphyMedia(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw HttpException('GIPHY media returned ${response.statusCode}.');
    }
    if (!hasContentType(response, const ['image'])) {
      await response.drain<void>();
      throw const HttpException('GIPHY returned unexpected media content.');
    }
    if (response.contentLength > _maximumGifBytes) {
      await response.drain<void>();
      throw const HttpException('GIPHY media exceeds the 25 MiB safety limit.');
    }
    return readBoundedResponse(
      response,
      maximumBytes: _maximumGifBytes,
      inactivityTimeout: _requestTimeout,
    );
  }

  Future<HttpClientResponse> _openGiphyMedia(Uri initialUri) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!_isGiphyMediaUri(uri)) {
        throw const HttpException('GIPHY redirected to an untrusted host.');
      }
      final addresses = kIsWeb
          ? null
          : await InternetAddress.lookup(uri.host).timeout(_requestTimeout);
      if (addresses != null &&
          (addresses.isEmpty || !addresses.every(isPublicInternetAddress))) {
        throw const HttpException('GIPHY media resolved to a private address.');
      }
      final request = await _http.getUrl(uri).timeout(_requestTimeout);
      request
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptHeader, 'image/gif,image/*;q=0.8');
      final response = await request.close().timeout(_requestTimeout);
      if (!_isRedirect(response.statusCode)) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || redirects == 3) {
        throw const HttpException('GIPHY returned an invalid redirect.');
      }
      uri = uri.resolve(location);
    }
    throw const HttpException('Too many GIPHY redirects.');
  }

  bool _isGiphyMediaUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      (uri.host == 'static.klipy.com' ||
          uri.host == 'giphy.com' ||
          uri.host.endsWith('.giphy.com'));

  bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  void dispose() => _http.close(force: true);
}
