import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

Map<String, dynamic> normalizeServerStorageUsage(Map<String, dynamic> raw) {
  int number(Object? value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        // Stay within JavaScript's exact integer range; bit shifts are 32-bit
        // on web and must not be used for a multi-gigabyte quota bound.
        value > 9007199254740991 ||
        value != value.roundToDouble()) {
      throw const FormatException('Invalid storage size.');
    }
    return value.toInt();
  }

  final used = number(raw['used_bytes']), quota = number(raw['quota_bytes']);
  if (quota == 0 || raw['categories'] is! Map) {
    throw const FormatException('Invalid storage usage.');
  }
  final categories = <String, Map<String, int>>{
    for (final key in ['images', 'videos', 'gifs', 'audio', 'legacy', 'other'])
      key: {'bytes': 0, 'files': 0},
  };
  for (final entry in (raw['categories'] as Map).entries) {
    if (entry.value is! Map) {
      throw const FormatException('Invalid storage category.');
    }
    final target = categories[entry.key] ?? categories['other']!;
    target['bytes'] = target['bytes']! + number(entry.value['bytes']);
    target['files'] = target['files']! + number(entry.value['files'] ?? 0);
  }
  final counted = categories.values.fold<int>(
    0,
    (sum, item) => sum + item['bytes']!,
  );
  if (counted > used) {
    throw const FormatException('Storage categories exceed total usage.');
  }
  categories['other']!['bytes'] =
      categories['other']!['bytes']! + used - counted;
  return {
    'used_bytes': used,
    'quota_bytes': quota,
    'remaining_bytes': used > quota ? 0 : quota - used,
    'categories': categories,
    'quota_enforced': raw['quota_enforced'] != false,
    'dry_run_pruning': raw['dry_run_pruning'] == true,
    'legacy_pruning':
        (raw['features'] is Map && raw['features']['legacy_pruning'] == true),
  };
}

class ServerStorageClient {
  ServerStorageClient(this.client, this.homeserver, this.token);
  final http.Client client;
  final Uri homeserver;
  final String token;
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, Object?>? body,
  ]) async {
    if (!{
      'usage',
      'profiles',
      'labels',
      'prune-preview',
      'prune',
    }.contains(action)) {
      throw ArgumentError('Unknown storage action');
    }
    if (homeserver.scheme != 'https' &&
        homeserver.host != '127.0.0.1' &&
        homeserver.host != 'localhost') {
      throw UnsupportedError('Server storage requires HTTPS.');
    }
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            homeserver.resolve('/_synapse/client/send/v1/$action'),
          )
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404 || response.statusCode == 501) {
      await response.stream.listen((_) {}).cancel();
      throw UnsupportedError(
        'Your homeserver does not support SeND storage controls.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > 512 * 1024) {
        throw StateError('Storage response is too large.');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw StateError(
        'Server storage request failed (${response.statusCode}).',
      );
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid storage response.');
    }
    return value;
  }
}
