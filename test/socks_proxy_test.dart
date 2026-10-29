import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
// Used by the pinned SOCKS adapter as well as this wire-protocol fixture.
// ignore: depend_on_referenced_packages
import 'package:async/async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/socks_proxy_config.dart';
import 'package:deltiecord/services/socks_proxy_native.dart';
import 'package:deltiecord/services/private_file_store.dart';

class _Proxy {
  late ServerSocket server;
  final sockets = <Socket>[];
  final bool auth, downgrade, stall, stallTls;
  final SecurityContext? tls;
  final int? responseSize;
  final String? responseBody;
  String? requestHeaders;
  String? target, user, password;
  final disconnected = Completer<void>();
  _Proxy({
    this.auth = false,
    this.downgrade = false,
    this.stall = false,
    this.stallTls = false,
    this.tls,
    this.responseSize,
    this.responseBody,
  });
  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) async {
      sockets.add(socket);
      final reader = ChunkedStreamReader<int>(socket.asBroadcastStream());
      Future<List<int>> read(int length) async {
        final bytes = await reader.readChunk(length);
        if (bytes.length != length) {
          throw const FormatException('Closed fixture');
        }
        return bytes;
      }

      try {
        final header = await read(2);
        final methods = await read(header[1]);
        if (stall) {
          await read(1);
          return;
        }
        socket.add([
          5,
          downgrade
              ? 0
              : auth
              ? 2
              : 0,
        ]);
        await socket.flush();
        if (downgrade) return;
        if (auth) {
          expect(methods, [2]);
          final info = await read(2);
          user = utf8.decode(await read(info[1]));
          final size = (await read(1)).single;
          password = utf8.decode(await read(size));
          socket.add([1, password == 'fixture-password' ? 0 : 1]);
          await socket.flush();
          if (password != 'fixture-password') return;
        }
        final command = await read(4);
        expect(command.sublist(0, 3), [5, 1, 0]);
        if (command[3] == 3) {
          target = ascii.decode(await read((await read(1)).single));
        } else {
          target = InternetAddress.fromRawAddress(
            Uint8List.fromList(await read(command[3] == 1 ? 4 : 16)),
          ).address;
        }
        await read(2);
        // A SOCKS bound-domain response must never trigger local DNS.
        final bound = ascii.encode('bound-address.invalid');
        socket.add([5, 0, 0, 3, bound.length, ...bound, 0, 0]);
        await socket.flush();
        if (stallTls) {
          while ((await reader.readChunk(1)).isNotEmpty) {}
          return;
        }
        if (tls != null) {
          await reader.cancel();
          final secure = await SecureSocket.secureServer(socket, tls!);
          sockets.add(secure);
          final secureReader = ChunkedStreamReader<int>(secure);
          await _http(secure, () => secureReader.readChunk(1));
        } else {
          await _http(socket, () => reader.readChunk(1));
        }
      } catch (_) {
        // Rejected authentication, TLS, timeout and cancellation are expected.
      } finally {
        socket.destroy();
        if (!disconnected.isCompleted) disconnected.complete();
      }
    });
  }

  Future<void> _http(Socket socket, Future<List<int>> Function() byte) async {
    final bytes = <int>[];
    while (bytes.length < 16384) {
      final b = await byte();
      if (b.isEmpty) return;
      bytes.addAll(b);
      if (bytes.length >= 4 &&
          ascii.decode(bytes.sublist(bytes.length - 4)) == '\r\n\r\n') {
        break;
      }
    }
    requestHeaders = ascii.decode(bytes);
    final body =
        responseBody ??
        (responseSize == null ? 'OK' : List.filled(responseSize!, 'x').join());
    socket.add(
      ascii.encode(
        'HTTP/1.1 200 OK\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n$body',
      ),
    );
    await socket.flush();
  }

  SocksProxyConfig config({String password = ''}) => SocksProxyConfig(
    enabled: true,
    host: '127.0.0.1',
    port: server.port,
    username: auth ? 'fixture-user' : '',
    password: password,
  );
  Future<void> close() async {
    for (final s in sockets) {
      s.destroy();
    }
    await server.close();
  }
}

Future<String> _request(
  _Proxy proxy,
  Uri uri, {
  SecurityContext? context,
  String password = '',
}) => HttpOverrides.runWithHttpOverrides(() async {
  final client = HttpClient(context: context);
  try {
    final response = await (await client.getUrl(uri)).close();
    return utf8.decode(
      await response.fold<List<int>>([], (a, b) => a..addAll(b)),
    );
  } finally {
    client.close(force: true);
  }
}, SocksHttpOverrides(proxy.config(password: password)));

void main() {
  test(
    'unsaved connection test uses SOCKS and strips query credentials',
    () async {
      final proxy = _Proxy(responseBody: '{"versions":["v1.11"]}');
      await proxy.start();
      addTearDown(proxy.close);
      final before = HttpOverrides.current;
      final stages = <String>[];
      await SocksProxy.testConnection(
        proxy.config(),
        Uri.parse('http://matrix.invalid/path?token=do-not-send#fragment'),
        stages.add,
      );
      expect(proxy.target, 'matrix.invalid');
      expect(proxy.requestHeaders, startsWith('GET /_matrix/client/versions '));
      expect(proxy.requestHeaders, isNot(contains('do-not-send')));
      expect(stages.join('\n'), contains('Proxy TCP connected'));
      expect(stages.join('\n'), contains('Connected through SOCKS5'));
      expect(identical(HttpOverrides.current, before), true);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'configuration rejects URLs, invalid ports and oversized credentials',
    () {
      for (final host in [
        'https://proxy.invalid',
        'host:1080',
        'user@host',
        'host/path',
      ]) {
        expect(SocksProxyConfig(host: host).validationError, isNotNull);
      }
      expect(const SocksProxyConfig(host: '::1').validationError, isNull);
      expect(const SocksProxyConfig(port: 70000).validationError, isNotNull);
      expect(
        SocksProxyConfig(
          username: List.filled(256, 'x').join(),
        ).validationError,
        isNotNull,
      );
      const config = SocksProxyConfig(
        username: 'private-user',
        password: 'private-password',
      );
      expect(config.toJson().containsKey('password'), isFalse);
      expect(config.toString(), isNot(contains('private-')));
      expect(config.allowDirectTraffic, isTrue);
    },
  );
  test(
    'HTTP uses remote target DNS and ignores the bound-domain DNS',
    () async {
      final proxy = _Proxy();
      await proxy.start();
      addTearDown(proxy.close);
      expect(
        await _request(
          proxy,
          Uri.parse('http://does-not-resolve.invalid/test'),
        ),
        'OK',
      );
      expect(proxy.target, 'does-not-resolve.invalid');
    },
  );
  test('username/password auth is sent only in the SOCKS handshake', () async {
    final proxy = _Proxy(auth: true);
    await proxy.start();
    addTearDown(proxy.close);
    expect(
      await _request(
        proxy,
        Uri.parse('http://target.invalid/'),
        password: 'fixture-password',
      ),
      'OK',
    );
    expect(proxy.user, 'fixture-user');
    expect(proxy.password, 'fixture-password');
  });
  test('wrong password fails closed without disclosing credentials', () async {
    final proxy = _Proxy(auth: true);
    await proxy.start();
    addTearDown(proxy.close);
    try {
      await _request(
        proxy,
        Uri.parse('http://target.invalid/'),
        password: 'secret-wrong-password',
      );
      fail('Must reject authentication');
    } catch (error) {
      expect('$error', isNot(contains('secret-wrong-password')));
    }
    expect(proxy.target, isNull);
  });
  test('a proxy cannot downgrade requested username/password auth', () async {
    final proxy = _Proxy(auth: true, downgrade: true);
    await proxy.start();
    addTearDown(proxy.close);
    await expectLater(
      _request(
        proxy,
        Uri.parse('http://target.invalid/'),
        password: 'fixture-password',
      ),
      throwsA(isA<SocketException>()),
    );
    expect(proxy.target, isNull);
  });
  for (final cancel in [false, true]) {
    test(
      'stalled handshake closes its socket (${cancel ? "cancel" : "deadline"})',
      () async {
        final proxy = _Proxy(stall: true);
        await proxy.start();
        addTearDown(proxy.close);
        final task = await connectThroughSocks(
          proxy.config(),
          Uri.parse('http://target.invalid/'),
          timeout: const Duration(milliseconds: 100),
        );
        final failing = expectLater(
          task.socket,
          throwsA(isA<SocketException>()),
        );
        if (cancel) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          task.cancel();
        }
        await failing;
        await proxy.disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }
  for (final cancel in [false, true]) {
    test(
      'stalled TLS handshake is bounded (${cancel ? "cancel" : "deadline"})',
      () async {
        final proxy = _Proxy(stallTls: true);
        await proxy.start();
        addTearDown(proxy.close);
        final task = await connectThroughSocks(
          proxy.config(),
          Uri.parse('https://target.invalid/'),
          timeout: const Duration(milliseconds: 100),
        );
        final failure = expectLater(
          task.socket.timeout(const Duration(seconds: 2)),
          throwsA(isA<SocketException>()),
        );
        if (cancel) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          task.cancel();
        }
        await failure;
        await proxy.disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }
  test('proxy passwords use secure storage, not the settings JSON', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('send-proxy-store-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/network_proxy.json');
    final store = SocksProxyStore(file: file);
    const config = SocksProxyConfig(
      enabled: true,
      username: 'fixture-user',
      password: 'fixture-password',
    );
    await store.save(config);
    expect(
      latin1.decode(await file.readAsBytes()),
      isNot(contains('fixture-password')),
    );
    expect(
      await readPrivateTextFile(file),
      isNot(contains('fixture-password')),
    );
    expect((await store.load()).password, 'fixture-password');
    if (!Platform.isWindows) expect((await file.stat()).mode & 63, 0);
    await file.writeAsString('damaged');
    await expectLater(store.load(), throwsA(isA<FormatException>()));
    await store.reset();
    expect((await store.load()).enabled, isFalse);
  });
  test(
    'HTTPS through SOCKS preserves certificate and hostname validation',
    () async {
      try {
        await Process.run('openssl', ['version']);
      } on ProcessException {
        markTestSkipped(
          'OpenSSL is required to generate the ephemeral TLS fixture.',
        );
        return;
      }
      final dir = await Directory.systemTemp.createTemp('send-socks-tls-');
      addTearDown(() => dir.delete(recursive: true));
      final generated = await Process.run('openssl', [
        'req',
        '-x509',
        '-newkey',
        'rsa:2048',
        '-nodes',
        '-keyout',
        '${dir.path}/key.pem',
        '-out',
        '${dir.path}/cert.pem',
        '-days',
        '1',
        '-subj',
        '/CN=proxy-test.invalid',
        '-addext',
        'subjectAltName=DNS:proxy-test.invalid',
      ]);
      expect(
        generated.exitCode,
        0,
        reason: 'Generate a local test certificate',
      );
      final serverContext = SecurityContext()
        ..useCertificateChain('${dir.path}/cert.pem')
        ..usePrivateKey('${dir.path}/key.pem');
      final trusted = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('${dir.path}/cert.pem');
      final proxy = _Proxy(tls: serverContext);
      await proxy.start();
      addTearDown(proxy.close);
      expect(
        await _request(
          proxy,
          Uri.parse('https://proxy-test.invalid/'),
          context: trusted,
        ),
        'OK',
      );
      expect(proxy.target, 'proxy-test.invalid');
      final large = _Proxy(tls: serverContext, responseSize: 512 * 1024);
      await large.start();
      addTearDown(large.close);
      final body = await _request(
        large,
        Uri.parse('https://proxy-test.invalid/large'),
        context: trusted,
      );
      expect(body.length, 512 * 1024);
      expect(body.replaceAll('x', ''), isEmpty);
      await expectLater(
        _request(proxy, Uri.parse('https://proxy-test.invalid/')),
        throwsA(isA<SocketException>()),
      );
      await expectLater(
        _request(
          proxy,
          Uri.parse('https://wrong-host.invalid/'),
          context: trusted,
        ),
        throwsA(isA<SocketException>()),
      );
    },
  );
}
