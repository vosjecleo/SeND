import '../models/socks_proxy_config.dart';

abstract final class SocksProxy {
  static const supported = false;
  static const enabled = false;
  static const blockDirectTraffic = false;
  static const configurationError = false;
  static const active = SocksProxyConfig();
  static Future<void> initialize() async {}
  static Future<SocksProxyConfig> load() async => active;
  static Future<void> save(SocksProxyConfig value) async =>
      throw UnsupportedError('Use browser or OS proxy settings.');
  static Future<void> reset() async {}
  static Future<void> testConnection(
    SocksProxyConfig config,
    Uri homeserver,
    void Function(String) report,
  ) async => throw UnsupportedError('Use browser or system proxy settings.');
  static void requireLocalPlayback(Uri uri) {}
}
