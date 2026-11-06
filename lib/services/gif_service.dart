import 'dart:convert';
import 'dart:async';
import 'platform_io.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, Listenable, ValueNotifier;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../version.dart';
import 'bounded_http.dart';
import 'public_network_address.dart';
import 'private_file_store.dart';
import 'socks_proxy.dart';
import 'browser_private_store.dart';
import 'personal_data.dart';
import '../models/saved_gif_reference.dart';
import 'encoded_image_dimensions.dart';
import 'gif_identity.dart';
import 'gif_category_cache.dart';
import 'gif_categories.dart';

class GifSearchResult {
  const GifSearchResult({
    required this.title,
    required this.previewUrl,
    required this.shareUrl,
    this.width,
    this.height,
    this.message,
    this.providerId,
  });

  final String title;
  final Uri previewUrl;
  final Uri shareUrl;
  final int? width, height;
  final SavedGifReference? message;
  final String? providerId;
  String? get _savedIdentity => message == null
      ? null
      : message!.identity ?? gifIdentityFor(message!.roomId, message!.eventId);
  bool matches(GifSearchResult other) =>
      shareUrl == other.shareUrl ||
      (_savedIdentity != null && _savedIdentity == other._savedIdentity) ||
      (providerId != null && providerId == other.providerId);
  double get aspectRatio =>
      width != null && height != null && width! > 0 && height! > 0
      ? (width! / height!).clamp(.1, 10).toDouble()
      : 1;
  static int? dimension(Object? value) {
    final n = value is num ? value.toInt() : int.tryParse('$value');
    return n != null && n > 0 && n <= 32768 ? n : null;
  }

  factory GifSearchResult.saved(
    SavedGifReference reference, {
    int? width,
    int? height,
  }) => GifSearchResult(
    title: 'GIF',
    previewUrl: reference.uri,
    shareUrl: reference.uri,
    message: reference,
    width: width,
    height: height,
  );

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
    Map? previewInfo;
    for (final formats in file.values.whereType<Map>()) {
      final gif = formats['gif'];
      if (gif is Map && gif['url'] == preview.toString()) previewInfo = gif;
    }
    return GifSearchResult(
      title: item['title']?.toString() ?? 'GIF',
      previewUrl: preview,
      shareUrl: media,
      width: dimension(previewInfo?['width']),
      height: dimension(previewInfo?['height']),
      providerId: item['slug'] is String ? 'klipy:${item['slug']}' : null,
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
      width: dimension(preview?['width']),
      height: dimension(preview?['height']),
    );
  }

  Map<String, Object> toJson() => {
    'title': title,
    'preview_url': previewUrl.toString(),
    'share_url': shareUrl.toString(),
    'width': ?width,
    'height': ?height,
    'provider_id': ?providerId,
    if (message != null) 'message': message!.toJson(),
  };

  static GifSearchResult? fromJson(Object? value) {
    if (value is! Map) return null;
    if (value.containsKey('message')) {
      final reference = SavedGifReference.fromJson(value['message']);
      return reference == null
          ? null
          : GifSearchResult.saved(
              reference,
              width: dimension(value['width']),
              height: dimension(value['height']),
            );
    }
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
      width: dimension(value['width']),
      height: dimension(value['height']),
      providerId: value['provider_id'] is String
          ? value['provider_id'] as String
          : null,
    );
  }
}

/// Provider-neutral picker/storage client. The proxy selects the provider;
/// provider-specific response parsing stays at this boundary.
/// SeND's rate-limited server proxy adds the shared application key, so
/// neither source archives nor release binaries contain that credential.
class GifSearchPage {
  const GifSearchPage({
    required this.items,
    required this.page,
    required this.hasMore,
  });
  final List<GifSearchResult> items;
  final int page;
  final bool hasMore;
  factory GifSearchPage.fromJson(Map<String, Object?> json, int requestedPage) {
    final payload = json['data'];
    final values = payload is Map ? payload['data'] : payload;
    final returnedPage = payload is Map ? payload['current_page'] : null;
    // Older proxies always return page one. Never append it repeatedly.
    if (returnedPage != null && returnedPage != requestedPage) {
      return GifSearchPage(
        items: const [],
        page: requestedPage,
        hasMore: false,
      );
    }
    final items = values is List
        ? values
              .whereType<Map>()
              .map(GifSearchResult.fromKlipy)
              .whereType<GifSearchResult>()
              .toList()
        : <GifSearchResult>[];
    return GifSearchPage(
      items: items,
      page: requestedPage,
      hasMore:
          items.isNotEmpty && (payload is Map && payload['has_next'] == true),
    );
  }
}

class GifSearchException implements Exception {
  const GifSearchException(this.message, this.code, {this.status});
  final String message, code;
  final int? status;
  @override
  String toString() => message;
}

class GifService {
  GifService();
  bool _disposed = false;
  Future<void> warmCategories() async {
    for (final query in gifCategorySearches) {
      if (_disposed) return;
      try {
        await categoryRequest(() => categoryLinks(query));
      } catch (error) {
        if (error is GifSearchException &&
            (error.status == 429 || error.code == 'http_429')) {
          return;
        }
      }
    }
  }

  static Future<File> _categoryFile() async => File(
    path.join(
      (await getApplicationSupportDirectory()).path,
      'deltiecord',
      'gif-category-links.json',
    ),
  );
  static final _categoryLinks = GifCategoryCache(
    read: () async {
      if (kIsWeb) return BrowserPrivateStore.read('gif-category-links');
      final file = await _categoryFile();
      if (!await privateFileExists(file) || await file.length() > 256 * 1024) {
        return null;
      }
      return readPrivateTextFile(file);
    },
    write: (value) async {
      if (kIsWeb) {
        await BrowserPrivateStore.write('gif-category-links', value);
      } else {
        await writePrivateTextFile(await _categoryFile(), value);
      }
    },
  );
  Future<List<GifSearchResult>> categoryLinks(String query) async =>
      (await _categoryLinks.get(
        query,
        () async =>
            (await _requestPage(
                  {
                    if (query.isEmpty) 'mode': 'trending' else 'q': query,
                    'page': '1',
                  },
                  1,
                  cacheResults: false,
                )).items
                .take(5)
                .map((gif) => Map<String, Object?>.from(gif.toJson()))
                .toList(),
      )).map(GifSearchResult.fromJson).whereType<GifSearchResult>().toList();
  Future<void> _categoryQueue = Future.value();
  Future<T> categoryRequest<T>(Future<T> Function() work) {
    final request = _categoryQueue.then((_) => work());
    _categoryQueue = request.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return request;
  }

  static final favouriteChanges = ValueNotifier<int>(0);

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
    ..userAgent = kIsWeb ? null : 'SeND/$deltiecordVersion';
  File? _favoritesFile;
  static List<GifSearchResult>? _favorites;
  static PersonalData? _account;
  static bool _accountScoped = false;
  static Future<Uint8List> Function(SavedGifReference)? _resolveSaved;
  static final _savedCache = <Uri, Uint8List>{};
  static int _savedBytes = 0;
  static void bind(
    PersonalData? account, {
    Future<Uint8List> Function(SavedGifReference)? resolveSaved,
  }) {
    if (!identical(_account, account)) {
      _savedCache.clear();
      _savedBytes = 0;
    }
    _accountScoped = true;
    _account = account;
    _resolveSaved = resolveSaved;
  }

  Listenable? get accountChanges => _account;

  List<GifSearchResult> get frequent {
    final account = _account;
    if (account == null) return const [];
    final usage = account.usage('gif').entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return usage
        .take(40)
        .map((e) => GifSearchResult.fromJson(account.get('gif:${e.key}')))
        .whereType<GifSearchResult>()
        .toList();
  }

  Future<void> recordSent(GifSearchResult gif) async {
    final account = _account;
    if (account == null) return;
    await account.set('gif:${gif.shareUrl}', gif.toJson());
    await account.recordUsage('gif', gif.shareUrl.toString());
  }

  Future<void> importDeviceFavourites() async {
    final account = _account;
    if (account == null) return;
    final legacy = await _deviceFavorites();
    for (final gif in legacy) {
      await account.set('fav.gif:${gif.shareUrl}', gif.toJson());
    }
  }

  static final _mediaCache = <Uri, Uint8List>{};
  static final _mediaRequests = <Uri, Future<Uint8List>>{};
  static int _cachedBytes = 0;
  static final _searchCache = <String, (DateTime, GifSearchPage)>{};
  static final _searchRequests = <String, Future<GifSearchPage>>{};
  String? lastFailureCode;

  Future<GifSearchPage> page({String query = '', int page = 1}) =>
      _requestPage({
        if (query.trim().isEmpty) 'mode': 'trending' else 'q': query.trim(),
        'page': '$page',
      }, page);

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
    return (await page()).items;
  }

  Future<List<GifSearchResult>> _request(
    Map<String, String> parameters,
  ) async => (await _requestPage(parameters, 1)).items;

  Future<GifSearchPage> _requestPage(
    Map<String, String> parameters,
    int page, {
    bool cacheResults = true,
  }) async {
    final base = kIsWeb
        ? Uri.base.resolve('/api/servers/klipy/search')
        : Uri.parse(_proxyUrl);
    if (base.scheme != 'https') {
      throw StateError('The GIF search proxy must use HTTPS.');
    }
    if (page < 1 || page > 10000 || (parameters['q']?.length ?? 0) > 100) {
      throw const GifSearchException(
        'Try a shorter GIF search.',
        'invalid_query',
      );
    }
    final uri = base.replace(queryParameters: parameters);
    final key = '${cacheResults ? '' : 'category:'}$uri';
    final cached = _searchCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 60)) {
      return cached.$2;
    }
    final pending = _searchRequests[key];
    if (pending != null) return pending;
    final future = _requestRetry(uri, page);
    _searchRequests[key] = future;
    try {
      final result = await future;
      if (cacheResults) _searchCache[key] = (DateTime.now(), result);
      while (_searchCache.length > 32) {
        _searchCache.remove(_searchCache.keys.first);
      }
      lastFailureCode = null;
      return result;
    } finally {
      if (identical(_searchRequests[key], future)) _searchRequests.remove(key);
    }
  }

  Future<GifSearchPage> _requestRetry(Uri uri, int page) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _http.getUrl(uri).timeout(_requestTimeout);
        request
          ..followRedirects = false
          ..headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(_requestTimeout);
        if (response.statusCode != HttpStatus.ok) {
          final status = response.statusCode;
          await response.listen((_) {}).cancel();
          throw GifSearchException(
            status == 429
                ? 'GIF search is busy. Try again shortly.'
                : 'GIF search is unavailable. Try again.',
            'http_$status',
            status: status,
          );
        }
        if (!hasContentType(response, const ['application/json']) ||
            response.contentLength > _maximumSearchBytes) {
          await response.listen((_) {}).cancel();
          throw const GifSearchException(
            'GIF search returned an invalid response.',
            'invalid_response',
          );
        }
        final body = utf8.decode(
          await readBoundedResponse(
            response,
            maximumBytes: _maximumSearchBytes,
            inactivityTimeout: _requestTimeout,
          ),
        );
        final json = jsonDecode(body);
        if (json is! Map<String, Object?>) {
          throw const GifSearchException(
            'GIF search returned an invalid response.',
            'invalid_response',
          );
        }
        return GifSearchPage.fromJson(json, page);
      } catch (error) {
        final retry =
            error is SocketException ||
            error is TimeoutException ||
            (error is GifSearchException &&
                {502, 503, 504}.contains(error.status));
        lastFailureCode = error is GifSearchException
            ? error.code
            : error is SocketException
            ? 'network'
            : error is TimeoutException
            ? 'timeout'
            : 'invalid_response';
        if (attempt == 0 && retry) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        if (error is GifSearchException) rethrow;
        throw GifSearchException(
          'Could not load GIFs. Try again.',
          lastFailureCode!,
        );
      }
    }
    throw const GifSearchException(
      'Could not load GIFs. Try again.',
      'unavailable',
    );
  }

  Future<List<GifSearchResult>> favorites() async {
    final account = _account;
    if (_accountScoped && account == null) return const [];
    if (account != null) {
      return account
          .favourites('gif')
          .map((id) => GifSearchResult.fromJson(account.get('fav.gif:$id')))
          .whereType<GifSearchResult>()
          .toList();
    }
    return _deviceFavorites();
  }

  Future<List<GifSearchResult>> _deviceFavorites() async {
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
          : await privateFileExists(file!)
          ? await readPrivateTextFile(file)
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
      // Do not let a later favourite write replace an unreadable source.
      _favorites = null;
      throw StateError('Could not open saved GIFs. Existing data was kept.');
    }
    return List.unmodifiable(_favorites!);
  }

  Future<bool> toggleFavorite(GifSearchResult gif) async {
    if (gif.message != null && _account == null) {
      throw StateError('Sign in to save this GIF.');
    }
    if (_accountScoped && _account == null) return false;
    if (_account case final account?) {
      final add = !isFavorite(gif);
      if (add) {
        await account.set('fav.gif:${gif.shareUrl}', gif.toJson());
      } else {
        for (final id in account.favourites('gif').toList()) {
          final saved = GifSearchResult.fromJson(account.get('fav.gif:$id'));
          if (saved != null && saved.matches(gif)) {
            await account.set('fav.gif:$id', null);
          }
        }
      }
      favouriteChanges.value++;
      return add;
    }
    await favorites();
    if (!kIsWeb && _favoritesFile == null) {
      final support = await getApplicationSupportDirectory();
      _favoritesFile = File(
        path.join(support.path, 'deltiecord', 'giphy_favorites.json'),
      );
    }
    final existing = _favorites!.indexWhere(
      (favorite) => favorite.matches(gif),
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
    favouriteChanges.value++;
    return nowFavorite;
  }

  bool isFavorite(GifSearchResult gif) => _account != null
      ? _account!.favourites('gif').any((id) {
          final saved = GifSearchResult.fromJson(_account!.get('fav.gif:$id'));
          return saved != null && saved.matches(gif);
        })
      : !_accountScoped &&
            (_favorites?.any((favorite) => favorite.matches(gif)) ?? false);

  Future<Uint8List> download(GifSearchResult gif) async {
    if (gif.message != null) {
      throw StateError('Send saved GIFs using their message reference.');
    }
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

  Future<Uint8List> preview(GifSearchResult gif) async {
    if (gif.message case final reference?) {
      final account = _account, resolver = _resolveSaved;
      if (account == null || resolver == null) {
        throw StateError('The original GIF is unavailable.');
      }
      final cached = _savedCache[gif.shareUrl];
      if (cached != null) return cached;
      final bytes = await resolver(reference);
      if (!identical(account, _account)) throw StateError('Account changed.');
      if (bytes.length <= 8 * 1024 * 1024) {
        _savedBytes -= _savedCache.remove(gif.shareUrl)?.length ?? 0;
        _savedCache[gif.shareUrl] = bytes;
        _savedBytes += bytes.length;
        while (_savedCache.length > 32 || _savedBytes > 32 * 1024 * 1024) {
          _savedBytes -= _savedCache.remove(_savedCache.keys.first)!.length;
        }
      }
      return bytes;
    }
    return download(
      GifSearchResult(
        title: gif.title,
        previewUrl: gif.animatedPreviewUrl,
        shareUrl: gif.animatedPreviewUrl,
      ),
    );
  }

  Future<Uint8List> _downloadMedia(Uri uri) async {
    if (!_isGiphyMediaUri(uri)) {
      throw StateError('The GIF provider returned an unexpected media URL.');
    }
    final response = await _openGiphyMedia(uri);
    if (response.statusCode != HttpStatus.ok) {
      await response.listen((_) {}).cancel();
      throw HttpException('GIPHY media returned ${response.statusCode}.');
    }
    if (!hasContentType(response, const ['image'])) {
      await response.listen((_) {}).cancel();
      throw const HttpException('GIPHY returned unexpected media content.');
    }
    if (response.contentLength > _maximumGifBytes) {
      await response.listen((_) {}).cancel();
      throw const HttpException('GIPHY media exceeds the 25 MiB safety limit.');
    }
    final bytes = await readBoundedResponse(
      response,
      maximumBytes: _maximumGifBytes,
      inactivityTimeout: _requestTimeout,
    );
    if (await readEncodedImageDimensions(
          bytes,
          maximumPixels: 32 * 1024 * 1024,
          maximumFramePixels: 256 * 1024 * 1024,
        ) ==
        null) {
      throw const HttpException('This GIF is too large to display safely.');
    }
    return bytes;
  }

  Future<HttpClientResponse> _openGiphyMedia(Uri initialUri) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!_isGiphyMediaUri(uri)) {
        throw const HttpException('GIPHY redirected to an untrusted host.');
      }
      final addresses = kIsWeb || SocksProxy.enabled
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
      await response.listen((_) {}).cancel();
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

  void dispose() {
    _disposed = true;
    _http.close(force: true);
  }
}
