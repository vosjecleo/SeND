import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:deltiecord/matrix/media_range_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'serves a non-aligned decrypted byte range without full download',
    () async {
      final plaintext = Uint8List.fromList(
        utf8.encode(
          List.filled(200, 'Deltiecord encrypted streaming range test ').join(),
        ),
      );
      final key = Uint8List.fromList(List.generate(32, (index) => index));
      final iv = Uint8List.fromList([
        12,
        34,
        56,
        78,
        90,
        12,
        34,
        56,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      Uint8List xorRange(
        Uint8List input,
        Uint8List key,
        Uint8List _,
        int blockOffset,
      ) => Uint8List.fromList([
        for (var index = 0; index < input.length; index++)
          input[index] ^ key[(blockOffset * 16 + index) % key.length],
      ]);
      final ciphertext = xorRange(plaintext, key, iv, 0);
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var bytesServed = 0;
      upstream.listen((request) async {
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer token',
        );
        final range = request.headers.value(HttpHeaders.rangeHeader)!;
        final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
        final start = int.parse(match.group(1)!);
        final end = int.parse(match.group(2)!);
        final bytes = ciphertext.sublist(start, end + 1);
        bytesServed += bytes.length;
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.contentLength = bytes.length
          ..add(bytes);
        await request.response.close();
      });

      final proxy = MediaRangeProxy(decryptor: xorRange);
      addTearDown(() async {
        await proxy.close();
        await upstream.close(force: true);
      });
      final local = await proxy.register(
        upstream: Uri.parse(
          'http://127.0.0.1:${upstream.port}/encrypted-video',
        ),
        accessToken: 'token',
        key: key,
        iv: iv,
        size: ciphertext.length,
        mimeType: 'video/mp4',
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(local);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=37-412');
      final response = await request.close();
      final actual = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );

      expect(response.statusCode, HttpStatus.partialContent);
      expect(actual.takeBytes(), plaintext.sublist(37, 413));
      expect(bytesServed, lessThan(plaintext.length));
    },
  );

  test('serves HTTP suffix ranges from the end of encrypted media', () async {
    final plaintext = Uint8List.fromList(List.generate(1024, (index) => index));
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((request) async {
      final match = RegExp(r'bytes=(\d+)-(\d+)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader)!)!;
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2)!);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..add(plaintext.sublist(start, end + 1));
      await request.response.close();
    });
    final proxy = MediaRangeProxy(decryptor: (input, _, _, _) => input);
    addTearDown(() async {
      await proxy.close();
      await upstream.close(force: true);
    });
    final local = await proxy.register(
      upstream: Uri.parse('http://127.0.0.1:${upstream.port}/media'),
      accessToken: 'token',
      key: Uint8List(32),
      iv: Uint8List(16),
      size: plaintext.length,
      mimeType: 'video/mp4',
    );
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(local);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=-64');
    final response = await request.close();
    final bytes = await response.fold<BytesBuilder>(
      BytesBuilder(),
      (builder, value) => builder..add(value),
    );
    expect(bytes.takeBytes(), plaintext.sublist(plaintext.length - 64));
  });
}
