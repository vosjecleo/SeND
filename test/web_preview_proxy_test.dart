import 'package:deltiecord/services/web_preview_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preview proxy keeps provider URL and range separate from its origin',
    () {
      final original = Uri.parse(
        'https://fxtwitter.com/user/status/123?x=1&y=2',
      );
      final result = webPreviewProxyUrl(original, range: 'bytes=0-1023');
      const configured = String.fromEnvironment(
        'WEB_PREVIEW_PROXY_URL',
        defaultValue: 'https://deltie.net/api/servers/preview',
      );
      expect(result.origin, Uri.parse(configured).origin);
      expect(result.path, Uri.parse(configured).path);
      expect(result.queryParameters, {
        'url': original.toString(),
        'kind': 'video',
        'range': 'bytes=0-1023',
      });
    },
  );
}
