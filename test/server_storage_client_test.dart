import 'dart:convert';
import 'package:deltiecord/services/server_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multi-gigabyte server quotas normalize on native and web', () {
    final usage = normalizeServerStorageUsage({
      'used_bytes': 900 * 1048576,
      'quota_bytes': 12 * 1073741824,
      'categories': {},
    });
    expect(usage['remaining_bytes'], 12 * 1073741824 - 900 * 1048576);
    expect((usage['categories'] as Map)['other']['bytes'], 900 * 1048576);
  });
  test(
    'storage uses same-homeserver bearer auth, no redirects or token URLs',
    () async {
      final client = MockClient((request) async {
        expect(request.url.origin, 'https://matrix.example.org');
        expect(request.url.path, '/_synapse/client/send/v1/profiles');
        expect(request.url.query, isEmpty);
        expect(request.followRedirects, false);
        expect(request.headers['Authorization'], 'Bearer synthetic-token');
        expect(jsonDecode(request.body)['users'], ['@a:example.org']);
        return http.Response('{"profiles":{}}', 200);
      });
      expect(
        await ServerStorageClient(
          client,
          Uri.parse('https://matrix.example.org'),
          'synthetic-token',
        ).call('profiles', {
          'users': ['@a:example.org'],
        }),
        {'profiles': {}},
      );
    },
  );
  test(
    'unsupported, oversized and error responses expose no server response or token',
    () async {
      Future<Map<String, dynamic>> run(int status, String body) =>
          ServerStorageClient(
            MockClient((_) async => http.Response(body, status)),
            Uri.parse('https://example.org'),
            'synthetic-token',
          ).call('usage');
      await expectLater(run(404, 'private response'), throwsUnsupportedError);
      await expectLater(run(200, 'x' * (512 * 1024 + 1)), throwsStateError);
      await expectLater(
        run(500, 'private response'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
    },
  );
}
