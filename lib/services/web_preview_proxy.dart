/// Only public, allowlisted providers are accepted by the server. It applies
/// DNS pinning, redirect validation, rate/concurrency and response-size limits.
Uri webPreviewProxyUrl(Uri original, {String kind = 'video', String? range}) =>
    Uri.https('deltie.net', '/api/servers/preview', {
      'url': original.toString(),
      'kind': kind,
      'range': ?range,
    });
