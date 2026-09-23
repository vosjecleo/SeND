import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:deltiecord/matrix/media_range_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final valid in [true, false]) {
    test(
      'encrypted media ${valid ? 'verifies before decoding' : 'rejects incorrect hash before decoding'}',
      () async {
        final bytes = Uint8List.fromList(List.generate(129, (i) => i));
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var downloads = 0;
        var decryptions = 0;
        upstream.listen((request) async {
          downloads++;
          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          request.response.contentLength = bytes.length;
          request.response.add(bytes);
          await request.response.close();
        });
        final proxy = MediaRangeProxy(
          decryptor: (input, _, _, _) {
            decryptions++;
            return input;
          },
        );
        final http = HttpClient();
        addTearDown(() async {
          http.close(force: true);
          await proxy.close();
          await upstream.close(force: true);
        });
        final uri = await proxy.register(
          upstream: Uri.parse('http://127.0.0.1:${upstream.port}/file'),
          accessToken: 'test',
          key: Uint8List(32),
          iv: Uint8List(16),
          size: bytes.length,
          mimeType: 'video/mp4',
          expectedSha256: valid
              ? Uint8List.fromList(sha256.convert(bytes).bytes)
              : Uint8List(32),
        );
        final response = await (await http.getUrl(uri)).close();
        await response.drain<void>();
        if (valid) {
          expect(response.statusCode, 200);
          expect(decryptions, greaterThan(0));
          final again = await (await http.getUrl(uri)).close();
          await again.drain<void>();
          expect(downloads, 1);
        } else {
          expect(response.statusCode, isNot(200));
          expect(decryptions, 0);
        }
      },
    );
  }
}
