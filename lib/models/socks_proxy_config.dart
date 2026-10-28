import 'dart:convert';

class SocksProxyConfig {
  const SocksProxyConfig({
    this.enabled = false,
    this.host = '127.0.0.1',
    this.port = 1080,
    this.username = '',
    this.password = '',
    this.allowDirectTraffic = true,
  });
  final bool enabled, allowDirectTraffic;
  final String host, username, password;
  final int port;

  String? get validationError {
    final value = host.trim();
    if (value.isEmpty ||
        value.length > 253 ||
        RegExp(r'[\s/@?#\\]').hasMatch(value) ||
        Uri.tryParse(
              'socks5://${value.contains(':') && !value.startsWith('[') ? '[$value]' : value}:$port',
            )?.host.isNotEmpty !=
            true) {
      return 'Use a hostname or IP address, not a URL or port.';
    }
    if (port < 1 || port > 65535) return 'Enter a port from 1 to 65535.';
    if (utf8.encode(username).length > 255 ||
        utf8.encode(password).length > 255) {
      return 'Use up to 255 UTF-8 bytes per username or password.';
    }
    if (password.isNotEmpty && username.isEmpty) {
      return 'Enter a proxy username too.';
    }
    return null;
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'host': host.trim(),
    'port': port,
    'username': username,
    'allow_direct': allowDirectTraffic,
  };
  factory SocksProxyConfig.fromJson(
    Map<String, dynamic> value, {
    String password = '',
  }) {
    final result = SocksProxyConfig(
      enabled: value['enabled'] as bool,
      host: value['host'] as String,
      port: value['port'] as int,
      username: value['username'] as String? ?? '',
      password: password,
      allowDirectTraffic: value['allow_direct'] as bool? ?? true,
    );
    if (result.validationError != null) {
      throw const FormatException('Invalid proxy settings');
    }
    return result;
  }
  @override
  String toString() =>
      'SocksProxyConfig(enabled: $enabled, credentials: redacted)';
}
