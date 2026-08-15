part of 'matrix_backend.dart';

extension _MatrixLinkPreviews on MatrixBackend {
  // Matrix URL previews are preferred. FxTwitter's public API is only a
  // provider fallback for X links; no FxTwitter source is included or copied.
  Future<void> _hydrateLinkPreviews(Timeline timeline) async {
    for (final event in timeline.events) {
      if (_linkPreviews.containsKey(event.eventId) ||
          event.type != EventTypes.Message ||
          event.hasAttachment) {
        continue;
      }
      final match = _webUrlPattern.firstMatch(
        event.calcUnlocalizedBody(
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
        ),
      );
      final rawUrl = match?.group(0)?.replaceFirst(RegExp(r'[.,;:!?]+$'), '');
      final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (url == null) {
        _linkPreviews[event.eventId] = null;
        continue;
      }
      // The standard endpoint lets the homeserver apply its SSRF protections
      // and cache metadata consistently with other Matrix clients.
      try {
        final preview = await _matrix.getUrlPreview(
          url,
          ts: event.originServerTs.millisecondsSinceEpoch,
        );
        final properties = preview.additionalProperties;
        Uint8List? imageBytes;
        final image = preview.ogImage;
        if (image != null) {
          imageBytes = await _previewImageBytes(image);
        }
        Uri? propertyUri(String key) {
          final value = properties[key];
          return value is String ? Uri.tryParse(value) : null;
        }

        String? propertyString(String key) {
          final value = properties[key];
          return value is String && value.trim().isNotEmpty
              ? value.trim()
              : null;
        }

        int? propertyInt(String key) {
          final value = properties[key];
          return value is int ? value : int.tryParse(value?.toString() ?? '');
        }

        final result = LinkPreview(
          url: url,
          title: propertyString('og:title'),
          description: propertyString('og:description'),
          siteName: propertyString('og:site_name'),
          imageBytes: imageBytes,
          videoUrl: propertyUri('og:video') ?? propertyUri('og:video:url'),
          width: propertyInt('og:video:width') ?? propertyInt('og:image:width'),
          height:
              propertyInt('og:video:height') ?? propertyInt('og:image:height'),
        );
        _linkPreviews[event.eventId] =
            result.title == null &&
                result.description == null &&
                result.imageBytes == null &&
                result.videoUrl == null
            ? await _directLinkPreview(url)
            : result;
      } catch (_) {
        _linkPreviews[event.eventId] = await _directLinkPreview(url);
      }
    }
  }

  Future<LinkPreview?> _directLinkPreview(Uri url) async {
    try {
      final fxPreview = await _fxTwitterPreview(url);
      if (fxPreview != null) return fxPreview;
      if (!await _isPublicWebUrl(url)) return null;
      final opened = await _openPublicResponse(url, accept: 'text/html');
      if (opened == null) return null;
      final (response, responseUri) = opened;
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > 2 * 1024 * 1024) {
        await response.drain<void>();
        return null;
      }
      final source = await _decodeUtf8Limited(response, 2 * 1024 * 1024);
      final document = html_parser.parse(source);
      String? meta(String property) {
        final element =
            document.querySelector('meta[property="$property"]') ??
            document.querySelector('meta[name="$property"]');
        final content = element?.attributes['content']?.trim();
        return content == null || content.isEmpty ? null : content;
      }

      Uri? resolved(String? value) {
        if (value == null) return null;
        return responseUri.resolve(value);
      }

      final imageUrl = resolved(meta('og:image') ?? meta('twitter:image'));
      final videoUrl = resolved(
        meta('og:video:secure_url') ?? meta('og:video:url') ?? meta('og:video'),
      );
      final pageTitle = document.querySelector('title')?.text.trim();
      final title =
          meta('og:title') ??
          meta('twitter:title') ??
          (pageTitle?.isNotEmpty == true ? pageTitle : null);
      final description =
          meta('og:description') ??
          meta('twitter:description') ??
          meta('description');
      if (title == null &&
          description == null &&
          imageUrl == null &&
          videoUrl == null) {
        return null;
      }
      return LinkPreview(
        url: url,
        title: title,
        description: description,
        siteName: meta('og:site_name') ?? url.host,
        imageBytes: imageUrl == null
            ? null
            : await _previewImageBytes(imageUrl),
        videoUrl: videoUrl,
        width: int.tryParse(
          meta('og:video:width') ?? meta('og:image:width') ?? '',
        ),
        height: int.tryParse(
          meta('og:video:height') ?? meta('og:image:height') ?? '',
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<LinkPreview?> _fxTwitterPreview(Uri url) async {
    if (!{
      'fxtwitter.com',
      'www.fxtwitter.com',
      'fixupx.com',
    }.contains(url.host)) {
      return null;
    }
    final match = RegExp(r'/status/(\d+)').firstMatch(url.path);
    final statusId = match?.group(1);
    if (statusId == null) return null;
    final apiUrl = Uri.https('api.fxtwitter.com', '/status/$statusId');
    final opened = await _openPublicResponse(apiUrl);
    if (opened == null) return null;
    final response = opened.$1;
    if (response.statusCode != HttpStatus.ok) return null;
    final json = jsonDecode(
      await _decodeUtf8Limited(response, 2 * 1024 * 1024),
    );
    if (json is! Map) return null;
    final tweet = json['tweet'];
    if (tweet is! Map) return null;
    final media = tweet['media'];
    final all = media is Map ? media['all'] : null;
    final firstMedia = all is List && all.isNotEmpty ? all.first : null;
    final mediaMap = firstMedia is Map ? firstMedia : null;
    final thumbnail = Uri.tryParse(
      mediaMap?['thumbnail_url']?.toString() ?? '',
    );
    final mediaUrl = Uri.tryParse(mediaMap?['url']?.toString() ?? '');
    final author = tweet['author'];
    final authorName = author is Map ? author['name']?.toString() : null;
    return LinkPreview(
      url: url,
      title: authorName == null ? 'Post on X' : '$authorName on X',
      description: tweet['text']?.toString(),
      siteName: 'X via FxTwitter',
      imageBytes: thumbnail?.hasScheme == true
          ? await _previewImageBytes(thumbnail!)
          : null,
      videoUrl: mediaMap?['type'] == 'video' && mediaUrl?.hasScheme == true
          ? mediaUrl
          : null,
      width: int.tryParse(mediaMap?['width']?.toString() ?? ''),
      height: int.tryParse(mediaMap?['height']?.toString() ?? ''),
    );
  }

  Future<Uint8List?> _previewImageBytes(Uri uri) async {
    if (uri.isScheme('mxc')) {
      final thumbnail = await _matrix.getContentThumbnail(
        uri.host,
        uri.pathSegments.join('/'),
        640,
        360,
        method: Method.scale,
        animated: true,
      );
      return thumbnail.data;
    }
    if (!await _isPublicWebUrl(uri)) return null;
    final opened = await _openPublicResponse(uri);
    if (opened == null) return null;
    final response = opened.$1;
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > 8 * 1024 * 1024) {
      await response.drain<void>();
      return null;
    }
    final bytes = await response.fold<List<int>>(<int>[], (all, chunk) {
      if (all.length + chunk.length > 8 * 1024 * 1024) {
        throw const HttpException('Preview image is too large.');
      }
      return all..addAll(chunk);
    });
    return Uint8List.fromList(bytes);
  }

  Future<bool> _isPublicWebUrl(Uri uri) async {
    if (!{'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty) {
      return false;
    }
    if (uri.host == 'localhost' || uri.host.endsWith('.localhost')) {
      return false;
    }
    final addresses = await InternetAddress.lookup(uri.host);
    return addresses.isNotEmpty && addresses.every(isPublicInternetAddress);
  }

  Future<(HttpClientResponse, Uri)?> _openPublicResponse(
    Uri initialUri, {
    String? accept,
  }) async {
    var uri = initialUri;
    for (var redirects = 0; redirects <= 4; redirects++) {
      if (!await _isPublicWebUrl(uri)) return null;
      final request = await _previewHttpClient.getUrl(uri);
      request.followRedirects = false;
      if (accept != null) request.headers.set(HttpHeaders.acceptHeader, accept);
      final response = await request.close();
      final remote = response.connectionInfo?.remoteAddress;
      if (remote != null && !isPublicInternetAddress(remote)) {
        await response.drain<void>();
        return null;
      }
      if (!_isRedirect(response.statusCode)) return (response, uri);
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null) return null;
      uri = uri.resolve(location);
    }
    return null;
  }

  bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  Future<String> _decodeUtf8Limited(
    HttpClientResponse response,
    int maximumBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maximumBytes) {
        throw const HttpException('Preview response is too large.');
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes());
  }
}
