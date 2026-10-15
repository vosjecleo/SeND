import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'linux_update.dart'
    show downloadUpdateFile, runUpdateCommand, UpdateCommand;
import 'update_checker.dart';
import 'update_progress.dart';

/// Keep the native delta engine offline except for our capability-protected
/// loopback relay. It cannot follow URLs or proxy environment from the control
/// file. All upstream requests use Dart's SOCKS-aware HTTP client.
Uint8List localizeZsyncControl(List<int> bytes, Uri local, int expectedSize) {
  var end = -1;
  for (var i = 0; i + 1 < bytes.length && i < 16384; i++) {
    if (bytes[i] == 10 && bytes[i + 1] == 10) {
      end = i;
      break;
    }
  }
  if (end < 0) throw const FormatException('Invalid zsync header.');
  final header = ascii.decode(bytes.sublist(0, end));
  final fields = <String, String>{};
  for (final line in header.split('\n')) {
    final split = line.indexOf(':');
    if (split < 1) throw const FormatException('Invalid zsync field.');
    final key = line.substring(0, split);
    if (!const {
      'zsync',
      'Filename',
      'MTime',
      'Blocksize',
      'Length',
      'Hash-Lengths',
      'URL',
      'SHA-1',
    }.contains(key)) {
      throw const FormatException('Unsupported zsync field.');
    }
    if (key == 'URL' || key == 'Filename') continue;
    if (fields.containsKey(key)) {
      throw const FormatException('Duplicate zsync field.');
    }
    fields[key] = line.substring(split + 1).trim();
  }
  if (!header.startsWith('zsync: ') ||
      int.tryParse(fields['Length'] ?? '') != expectedSize) {
    throw const FormatException('Wrong zsync target.');
  }
  final block = int.tryParse(fields['Blocksize'] ?? '') ?? 0;
  if (block < 512 || block > 1024 * 1024 || (block & (block - 1)) != 0) {
    throw const FormatException('Invalid zsync block size.');
  }
  // Filename cannot choose a local source/output path. -i and -o are explicit.
  final rewritten = fields.entries
      .map((e) => '${e.key}: ${e.value}')
      .join('\n');
  return Uint8List.fromList([
    ...ascii.encode('$rewritten\nFilename: target.AppImage\nURL: $local\n\n'),
    ...bytes.sublist(end + 2),
  ]);
}

Future<void> applyAppImageDelta({
  required HttpClient client,
  required ReleaseArtifact artifact,
  required ReleaseArtifact control,
  required File original,
  required File destination,
  required File helper,
  UpdateCommand? command,
  void Function(UpdateProgress)? progress,
}) async {
  final raw = File('${destination.path}.zsync.download');
  await downloadUpdateFile(client, control, raw);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final token = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final local = Uri.parse('http://127.0.0.1:${server.port}/$token');
  var active = 0, requests = 0, transferred = 0;
  final work = <Future<void>>[];
  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path != local.path ||
        request.method != 'GET' ||
        active >= 4 ||
        ++requests > 512) {
      response.statusCode = 403;
      await response.close();
      return;
    }
    active++;
    try {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null &&
          (range.length > 8192 ||
              !RegExp(r'^bytes=\d+-\d*(?:,\s*\d+-\d*)*$').hasMatch(range))) {
        throw const FormatException('Invalid delta range.');
      }
      if (range != null) {
        for (final pair in range.substring(6).split(',')) {
          final parts = pair.trim().split('-');
          final start = int.parse(parts[0]);
          final end = parts[1].isEmpty
              ? artifact.size - 1
              : int.parse(parts[1]);
          if (start < 0 || end < start || end >= artifact.size) {
            throw const FormatException('Delta range exceeds update.');
          }
        }
      }
      final upstream = await client
          .getUrl(artifact.url)
          .timeout(const Duration(seconds: 15));
      upstream.followRedirects = false;
      upstream.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
      final input = await upstream.close().timeout(const Duration(seconds: 20));
      if (input.statusCode != 200 && input.statusCode != 206) {
        throw const HttpException('Delta download failed.');
      }
      response.statusCode = input.statusCode;
      for (final name in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = input.headers.value(name);
        if (value != null) response.headers.set(name, value);
      }
      if (input.contentLength >= 0) {
        response.contentLength = input.contentLength;
      } else {
        // Classic zsync does not decode HTTP chunk framing. Dart has already
        // decoded the upstream stream; delimit the local response by EOF.
        response.headers.chunkedTransferEncoding = false;
        response.persistentConnection = false;
      }
      await for (final bytes in input.timeout(const Duration(seconds: 30))) {
        transferred += bytes.length;
        if (transferred > artifact.size * 2 + 1024 * 1024) {
          throw const FormatException('Delta download limit exceeded.');
        }
        response.add(bytes);
        await response.flush();
        progress?.call(
          UpdateProgress('Downloading changed AppImage data', null),
        );
      }
    } catch (_) {
      try {
        response.statusCode = 502;
      } catch (_) {}
    } finally {
      active--;
      try {
        await response.close();
      } catch (_) {}
    }
  }

  server.listen((request) {
    work.add(serve(request));
  });
  try {
    final localized = localizeZsyncControl(
      await raw.readAsBytes(),
      local,
      artifact.size,
    );
    final file = File('${destination.path}.zsync');
    await file.writeAsBytes(localized, flush: true);
    final code = await (command ?? runUpdateCommand)(helper.path, [
      '-q',
      '-i',
      original.path,
      '-o',
      destination.path,
      file.path,
    ], destination.parent.path);
    if (code != 0) throw StateError('Delta update could not be completed.');
  } finally {
    await server.close(force: true);
    await Future.wait(work);
  }
}
