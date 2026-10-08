/// Only public, allowlisted providers are accepted by the server. It applies
/// DNS pinning, redirect validation, rate/concurrency and response-size limits.
Uri webPreviewProxyUrl(Uri original, {String kind = 'video', String? range}) =>
    Uri.parse(
      const String.fromEnvironment(
        'WEB_PREVIEW_PROXY_URL',
        defaultValue: 'https://deltie.net/api/servers/preview',
      ),
    ).replace(
      queryParameters: {
        'url': original.toString(),
        'kind': kind,
        'range': ?range,
      },
    );
