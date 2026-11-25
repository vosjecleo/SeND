/// Only public, allowlisted providers are accepted by the server. It applies
/// DNS pinning, redirect validation, rate/concurrency and response-size limits.
final _previewProxyEndpoint = Uri.parse(
  const String.fromEnvironment(
    'WEB_PREVIEW_PROXY_URL',
    defaultValue: 'https://deltie.net/api/servers/preview',
  ),
);

bool isWebPreviewProxyUrl(Uri url) =>
    url.scheme == _previewProxyEndpoint.scheme &&
    url.authority == _previewProxyEndpoint.authority &&
    url.path == _previewProxyEndpoint.path;

Uri webPreviewProxyUrl(Uri original, {String kind = 'video', String? range}) =>
    _previewProxyEndpoint.replace(
      queryParameters: {
        'url': isWebPreviewProxyUrl(original)
            ? original.queryParameters['url']
            : original.toString(),
        'kind': kind,
        'range': ?range,
      },
    );
