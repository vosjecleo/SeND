import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Only normalized artwork is published, never local paths, source URLs or
/// embedded metadata. Small LRU prevents fetching/decoding on each scan.
class ActivityArtworkCache {
  final _cache = <String, Uint8List?>{};
  Future<Uint8List?> load(String source) async {
    final uri = Uri.tryParse(source);
    if (uri == null || source.isEmpty) return null;
    try {
      var key = source;
      if (uri.scheme == 'file') {
        if (uri.host.isNotEmpty && uri.host != 'localhost') return null;
        final stat = await File.fromUri(uri).stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > 4 * 1024 * 1024) {
          return null;
        }
        key = '$source:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      }
      if (_cache.containsKey(key)) {
        final value = _cache.remove(key);
        _cache[key] = value;
        return value;
      }
      final bytes = await _read(uri);
      final image = bytes == null
          ? null
          : await Isolate.run(_ArtworkDecode(bytes).call);
      // Retry temporary failures next scan, but keep successful covers bounded.
      if (image != null) {
        _cache[key] = image;
        while (_cache.length > 24) {
          _cache.remove(_cache.keys.first);
        }
      }
      return image;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _read(Uri uri) async {
    if (uri.scheme == 'file') {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in File.fromUri(
        uri,
      ).openRead().timeout(const Duration(seconds: 3))) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    }
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      return null;
    }
    // Remote metadata is untrusted: no redirects, credentials or private hosts.
    final addresses = await InternetAddress.lookup(
      uri.host,
    ).timeout(const Duration(seconds: 3));
    if (addresses.isEmpty || addresses.any((a) => !_publicAddress(a))) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final deadline = Timer(
      const Duration(seconds: 8),
      () => client.close(force: true),
    );
    // Pin the checked address, preserving the original hostname for TLS.
    client.connectionFactory = (url, proxyHost, proxyPort) =>
        Socket.startConnect(addresses.first, url.port);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200 ||
          response.contentLength > 4 * 1024 * 1024) {
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 4))) {
        if (bytes.length + chunk.length > 4 * 1024 * 1024) return null;
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
  }
}

bool _publicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv6) {
    // Accept only global unicast; excludes local and IPv4-mapped addresses.
    return (b[0] & 0xe0) == 0x20;
  }
  return b[0] != 0 &&
      b[0] != 10 &&
      b[0] != 127 &&
      b[0] < 224 &&
      !(b[0] == 169 && b[1] == 254) &&
      !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
      !(b[0] == 192 && b[1] == 168) &&
      !(b[0] == 100 && b[1] >= 64 && b[1] <= 127);
}

Uint8List? normalizeActivityArtwork(Uint8List bytes) {
  if (bytes.length > 4 * 1024 * 1024) return null;
  try {
    final decoder = img.findDecoderForData(bytes);
    if (decoder is! img.PngDecoder &&
        decoder is! img.JpegDecoder &&
        decoder is! img.WebPDecoder) {
      return null;
    }
    final info = decoder!.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width > 2048 ||
        info.height > 2048) {
      return null;
    }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) return null;
    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 384 : null,
      height: decoded.height > decoded.width ? 384 : null,
    );
    // Fresh image discards EXIF/text/profile chunks from source artwork.
    final clean = img.Image(
      width: resized.width,
      height: resized.height,
      numChannels: 4,
    );
    img.compositeImage(clean, resized);
    return Uint8List.fromList(img.encodePng(clean));
  } catch (_) {
    return null;
  }
}

class _ArtworkDecode {
  const _ArtworkDecode(this.bytes);
  final Uint8List bytes;
  Uint8List? call() => normalizeActivityArtwork(bytes);
}
