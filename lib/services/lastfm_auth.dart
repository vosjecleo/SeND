import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'platform_io.dart';

/// App credentials, not credentials that each end user must obtain. Like other
/// desktop Last.fm clients, packaged application secrets are extractable; they
/// are not user passwords. Do not reuse another application's registration.
class LastFmAuth {
  LastFmAuth({
    this.apiKey = const String.fromEnvironment('LASTFM_API_KEY'),
    this.secret = const String.fromEnvironment('LASTFM_API_SECRET'),
    this.transport,
  });
  final String apiKey, secret;
  final Future<Map<String, dynamic>> Function(Map<String, String>)? transport;
  bool get configured => apiKey.isNotEmpty && secret.isNotEmpty;

  Future<String> begin() async {
    final data = await _call({'method': 'auth.getToken'});
    final token = data['token'];
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{16,256}$').hasMatch(token)) {
      throw const LastFmAuthError(
        'Last.fm returned an invalid login token. Please try again.',
      );
    }
    return token;
  }

  Uri authorizationUrl(String token) => Uri.https('www.last.fm', '/api/auth/', {
    'api_key': apiKey,
    'token': token,
  });

  Future<String> finish(String token) async {
    final data = await _call({'method': 'auth.getSession', 'token': token});
    final session = data['session'];
    if (session is! Map ||
        session['name'] is! String ||
        (session['name'] as String).isEmpty ||
        session['key'] is! String) {
      throw const LastFmAuthError(
        'Last.fm did not confirm your account. Please try again.',
      );
    }
    // Presence only reads a public feed. Do not retain the write-capable session
    // key, and never scrobble or alter the user's library.
    return session['name'] as String;
  }

  Future<Map<String, dynamic>> _call(Map<String, String> input) async {
    if (!configured) {
      throw const LastFmAuthError(
        'Last.fm linking is not configured in this build.',
      );
    }
    final params = {...input, 'api_key': apiKey};
    final keys = params.keys.toList()..sort();
    params['api_sig'] = md5
        .convert(
          utf8.encode('${keys.map((k) => '$k${params[k]}').join()}$secret'),
        )
        .toString();
    params['format'] = 'json';
    final data = await (transport?.call(params) ?? _request(params));
    if (data['error'] != null) {
      throw LastFmAuthError(switch (data['error']) {
        14 => 'Please approve SeND in your browser first, then try again.',
        4 || 15 =>
          'This login attempt expired. Close this window and connect again.',
        10 || 26 => 'SeND’s Last.fm application credentials need updating.',
        29 => 'Last.fm is rate-limiting requests. Please try again later.',
        _ => 'Last.fm could not complete linking. Please try again.',
      });
    }
    return data;
  }

  Future<Map<String, dynamic>> _request(Map<String, String> params) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(
        Uri.https('ws.audioscrobbler.com', '/2.0/'),
      );
      request.followRedirects = false;
      request.headers.contentType = ContentType(
        'application',
        'x-www-form-urlencoded',
      );
      request.write(Uri(queryParameters: params).query);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > 128 * 1024) {
          throw const FormatException();
        }
        bytes.addAll(chunk);
      }
      final data = jsonDecode(utf8.decode(bytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } catch (_) {
      throw const LastFmAuthError(
        'Could not reach Last.fm. Check your connection and try again.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class LastFmAuthError implements Exception {
  const LastFmAuthError(this.message);
  final String message;
  @override
  String toString() => message;
}
