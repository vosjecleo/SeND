import 'dart:convert';
import 'dart:io';
import 'package:deltiecord/services/auth_browser_native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'loopback callback is scoped, not cached and never reflects credentials',
    () async {
      final browser = await AuthBrowser.prepare('test-nonce');
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await browser.close();
      });
      expect(browser.redirect.host, '127.0.0.1');
      expect(browser.redirect.port, greaterThan(0));
      final wrong = await (await client.getUrl(
        browser.redirect.replace(path: '/unrelated'),
      )).close();
      expect(wrong.statusCode, 404);
      await wrong.drain<void>();
      final callback = browser.redirect.replace(
        queryParameters: {
          'state': 'test-nonce',
          'loginToken': 'not-a-real-token',
        },
      );
      final response = await (await client.getUrl(callback)).close();
      expect(response.headers.value('cache-control'), 'no-store');
      final body = await utf8.decoder.bind(response).join();
      expect(body, isNot(contains('not-a-real-token')));
      expect(body, contains('history.replaceState'));
    },
  );
  test('cancellation before browser launch closes the pending flow', () async {
    final browser = await AuthBrowser.prepare('cancel-test');
    await browser.close();
    await expectLater(
      browser.authenticate(Uri.parse('https://example.org/authorize')),
      throwsStateError,
    );
    await browser.close(); // Idempotent cleanup.
  });
}
