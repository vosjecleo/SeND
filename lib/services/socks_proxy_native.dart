import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socks5_proxy/enums.dart';
// Pinned socket adapter only. Handshake/auth/DNS/cancellation are handled here.
// ignore: implementation_imports
import 'package:socks5_proxy/src/client/socks_client.dart';
import '../models/socks_proxy_config.dart';
import 'private_file_store.dart';

class SocksProxyStore {
  SocksProxyStore({this.file, FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  final File? file;
  final FlutterSecureStorage storage;
  Future<File> _file() async =>
      file ??
      File(
        '${(await getApplicationSupportDirectory()).path}/deltiecord/network_proxy.json',
      );
  Future<SocksProxyConfig> load({bool forEditing = false}) async {
    final target = await _file();
    if (!await privateFileExists(target)) return const SocksProxyConfig();
    final value =
        jsonDecode(await readPrivateTextFile(target)) as Map<String, dynamic>;
    final secretKey = value['secret_key'] as String?;
    final password =
        secretKey == null || (!forEditing && value['enabled'] == false)
        ? ''
        : await storage.read(key: secretKey);
    if (password == null) throw StateError('Proxy password unavailable');
    return SocksProxyConfig.fromJson(value, password: password);
  }

  Future<void> save(SocksProxyConfig value) async {
    if (value.validationError != null) {
      throw const FormatException('Invalid proxy settings');
    }
    final target = await _file();
    String? oldKey;
    if (await privateFileExists(target)) {
      try {
        oldKey =
            (jsonDecode(await readPrivateTextFile(target)) as Map)['secret_key']
                as String?;
      } catch (_) {}
    }
    final key = value.password.isEmpty
        ? null
        : 'send.socks5.${List.generate(24, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    if (key != null) await storage.write(key: key, value: value.password);
    try {
      await writePrivateTextFile(
        target,
        jsonEncode({...value.toJson(), 'secret_key': ?key}),
      );
    } catch (_) {
      if (key != null) {
        try {
          await storage.delete(key: key);
        } catch (_) {}
      }
      rethrow;
    }
    if (oldKey != null) {
      try {
        await storage.delete(key: oldKey);
      } catch (_) {}
    }
  }

  Future<void> reset() async {
    // Works even if the keyring is locked or the saved JSON is damaged.
    await save(const SocksProxyConfig());
  }
}

abstract final class SocksProxy {
  static const supported = true;
  static final store = SocksProxyStore();
  static SocksProxyConfig _active = const SocksProxyConfig();
  static SocksProxyConfig get active => _active;
  static bool configurationError = false;
  static bool get enabled => configurationError || _active.enabled;
  static bool get blockDirectTraffic =>
      configurationError || (_active.enabled && !_active.allowDirectTraffic);
  static Future<void>? _initializing;
  static Future<void> initialize() => _initializing ??= _initialize();
  static Future<void> _initialize() async {
    try {
      _active = await store.load();
    } catch (_) {
      configurationError = true;
    }
    if (enabled) {
      HttpOverrides.global = SocksHttpOverrides(
        _active,
        configurationError: configurationError,
      );
    }
    try {
      await _nativePolicy(blockDirectTraffic);
    } catch (_) {
      configurationError = true;
      HttpOverrides.global = SocksHttpOverrides(
        _active,
        configurationError: true,
      );
    }
  }

  static Future<void> _nativePolicy(bool block) async {
    if (!Platform.isAndroid) return;
    try {
      await const MethodChannel(
        'net.deltie.send/network_privacy',
      ).invokeMethod<void>('setProxyPolicy', {'block': block});
    } on MissingPluginException {
      // Headless notification engines use the policy persisted by the UI.
    }
  }

  static Future<SocksProxyConfig> load() => store.load(forEditing: true);
  static Future<void> save(SocksProxyConfig value) async {
    await _nativePolicy(
      blockDirectTraffic || (value.enabled && !value.allowDirectTraffic),
    );
    await store.save(value);
  }

  static Future<void> reset() async {
    await store.reset();
    // A running strict session remains strict until restart.
    await _nativePolicy(blockDirectTraffic);
  }

  static Future<void> testConnection(
    SocksProxyConfig config,
    Uri homeserver,
    void Function(String) report,
  ) async {
    if (config.validationError case final error?) throw FormatException(error);
    if (!{'https', 'http'}.contains(homeserver.scheme) ||
        homeserver.host.isEmpty ||
        homeserver.userInfo.isNotEmpty) {
      throw const FormatException('Invalid test server.');
    }
    final target = Uri(
      scheme: homeserver.scheme,
      host: homeserver.host,
      port: homeserver.hasPort ? homeserver.port : null,
      path: '/_matrix/client/versions',
    );
    final clock = Stopwatch()..start();
    void stage(String text) => report('${clock.elapsedMilliseconds} ms: $text');
    final client = SocksHttpOverrides(
      config,
      onStage: stage,
    ).createHttpClient(null);
    final deadline = Timer(
      const Duration(seconds: 25),
      () => client.close(force: true),
    );
    try {
      stage('Starting test');
      final request = await client.getUrl(target);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      stage('HTTP ${response.statusCode}');
      final bytes = <int>[];
      await for (final part in response.timeout(const Duration(seconds: 5))) {
        if (bytes.length + part.length > 65536) {
          throw const FormatException('Response too large.');
        }
        bytes.addAll(part);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['versions'] is! List) {
        throw const FormatException(
          'The server did not return Matrix versions.',
        );
      }
      stage('Connected through SOCKS5. Settings were not saved.');
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
  }

  static void requireLocalPlayback(Uri uri) {
    if (blockDirectTraffic &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        !(uri.host == '127.0.0.1' && uri.path.startsWith('/media/'))) {
      throw StateError(
        'Direct playback is blocked by your proxy settings. Download the file to play it.',
      );
    }
  }
}

/// No direct fallback, local target DNS lookup, certificate exceptions or
/// proxy credentials in URLs. A restart applies one snapshot to all clients.
class SocksHttpOverrides extends HttpOverrides {
  SocksHttpOverrides(
    this.config, {
    this.configurationError = false,
    this.onStage,
  });
  final SocksProxyConfig config;
  final bool configurationError;
  final void Function(String)? onStage;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, _, _) async {
      if (configurationError) {
        throw const SocketException('Proxy settings could not be loaded');
      }
      return connectThroughSocks(
        config,
        uri,
        context: context,
        onStage: onStage,
      );
    };
    return client;
  }
}

Future<ConnectionTask<Socket>> connectThroughSocks(
  SocksProxyConfig config,
  Uri uri, {
  SecurityContext? context,
  Duration timeout = const Duration(seconds: 20),
  void Function(String)? onStage,
}) async {
  Socket? current;
  ServerSocket? relayServer;
  Socket? relayPeer;
  Socket? relayClient;
  final accepted = <Socket>[];
  var cancelled = false;
  void cancel() {
    cancelled = true;
    current?.destroy();
    relayPeer?.destroy();
    relayClient?.destroy();
    for (final socket in accepted) {
      socket.destroy();
    }
    unawaited(relayServer?.close());
  }

  final deadline = Timer(timeout, cancel);
  Future<Socket> connect() async {
    try {
      final host = config.host.replaceAll(RegExp(r'^\[|\]$'), '');
      onStage?.call('Resolving/connecting to proxy');
      current = await Socket.connect(host, config.port, timeout: timeout);
      onStage?.call('Proxy TCP connected');
      if (cancelled) throw const SocketException('Proxy connection cancelled');
      final tunnel = _SocksTunnel(current!);
      await tunnel.handshake(uri, config, onStage);
      if (cancelled) throw const SocketException('Proxy connection cancelled');
      if (uri.scheme == 'https' || uri.scheme == 'wss') {
        onStage?.call('Checking server TLS certificate');
        // Retain the real proxy socket during TLS negotiation. Dart detaches
        // the input Socket during SecureSocket.secure, so destroying that
        // detached object cannot cancel a stalled TLS handshake. A private
        // loopback pair leaves us an independently closable transport endpoint.
        relayServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final listener = relayServer!.listen((socket) {
          if (cancelled) {
            socket.destroy();
          } else {
            accepted.add(socket);
          }
        });
        final local = await Socket.connect(
          InternetAddress.loopbackIPv4,
          relayServer!.port,
          timeout: timeout,
        );
        relayClient = local;
        while (!cancelled && !accepted.any((s) => s.remotePort == local.port)) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        await listener.cancel();
        await relayServer!.close();
        relayServer = null;
        for (final peer in accepted) {
          if (peer.remotePort == local.port && relayPeer == null) {
            relayPeer = peer;
          } else {
            peer.destroy();
          }
        }
        if (cancelled || relayPeer == null) {
          local.destroy();
          throw const SocketException('Proxy connection cancelled');
        }
        final peer = relayPeer!;
        unawaited(
          tunnel.forwardTo(peer).catchError((Object _) {
            peer.destroy();
          }),
        );
        unawaited(
          tunnel
              .addStream(peer)
              .then(
                (_) async {
                  await tunnel.close();
                },
                onError: (Object _) {
                  tunnel.destroy();
                },
              ),
        );
        current = await SecureSocket.secure(
          local,
          host: uri.host,
          context: context,
          supportedProtocols: const ['http/1.1'],
        );
        onStage?.call('TLS verified');
        current!.done.whenComplete(() {
          peer.destroy();
          tunnel.destroy();
        }).ignore();
      } else {
        current = tunnel;
      }
      if (cancelled) throw const SocketException('Proxy connection cancelled');
      return current!;
    } catch (_) {
      current?.destroy();
      relayPeer?.destroy();
      relayClient?.destroy();
      for (final socket in accepted) {
        socket.destroy();
      }
      await relayServer?.close();
      throw const SocketException('Could not connect through the SOCKS5 proxy');
    } finally {
      deadline.cancel();
    }
  }

  return ConnectionTask.fromSocket(connect(), () {
    deadline.cancel();
    cancel();
  });
}

class _SocksTunnel extends SocksSocket {
  _SocksTunnel(Socket socket)
    : super.protected(socket, SocksConnectionType.connect);
  StreamSubscription<List<int>>? _source;
  Stream<Uint8List>? _input;
  @override
  Stream<Uint8List> get stream => _input ??= socket.asBroadcastStream(
    onListen: (subscription) {
      _source = subscription;
      subscription.resume();
    },
    onCancel: (subscription) => subscription.pause(),
  );

  Future<void> forwardTo(Socket destination) async {
    final done = Completer<void>();
    stream.listen(
      (bytes) {
        _source?.pause();
        destination.add(bytes);
        destination.flush().then(
          (_) => _source?.resume(),
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
            destroy();
          },
        );
      },
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    await destination.close();
  }

  Future<void> handshake(
    Uri target,
    SocksProxyConfig config,
    void Function(String)? report,
  ) async {
    final method = config.username.isEmpty ? 0 : 2;
    add([5, 1, method]);
    await flush();
    final greeting = await readBytes(2);
    if (greeting[0] != 5 || greeting[1] != method) {
      throw const FormatException('Proxy rejected the authentication method');
    }
    if (method == 2) {
      report?.call('Authenticating with proxy');
      final user = utf8.encode(config.username),
          password = utf8.encode(config.password);
      add([1, user.length, ...user, password.length, ...password]);
      await flush();
      final auth = await readBytes(2);
      if (auth[0] != 1 || auth[1] != 0) {
        throw const FormatException('Proxy authentication failed');
      }
    }
    report?.call('Opening target tunnel (destination DNS handled by proxy)');
    final address = InternetAddress.tryParse(target.host);
    final domain = address == null ? ascii.encode(target.host) : null;
    if (domain != null && (domain.isEmpty || domain.length > 255)) {
      throw const FormatException('Invalid destination hostname');
    }
    final port = target.hasPort
        ? target.port
        : (target.scheme == 'https' || target.scheme == 'wss' ? 443 : 80);
    add([
      5,
      1,
      0,
      if (address != null) ...[
        address.type == InternetAddressType.IPv4 ? 1 : 4,
        ...address.rawAddress,
      ] else ...[
        3,
        domain!.length,
        ...domain,
      ],
      (port >> 8) & 255,
      port & 255,
    ]);
    await flush();
    final reply = await readBytes(4);
    if (reply[0] != 5 || reply[1] != 0 || reply[2] != 0) {
      throw const FormatException('Proxy refused the connection');
    }
    final length = switch (reply[3]) {
      1 => 4,
      4 => 16,
      3 => await readUint8(),
      _ => throw const FormatException('Invalid proxy reply'),
    };
    if (length <= 0) throw const FormatException('Invalid bound address');
    // This address is not a target to resolve. Never leak proxy-supplied DNS.
    await readBytes(length + 2);
    await data.cancel();
    report?.call('SOCKS5 tunnel established');
  }
}
