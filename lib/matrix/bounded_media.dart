import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import '../services/bounded_http.dart';
import '../services/encoded_image_dimensions.dart';

/// All automatic Matrix media reads share a bounded working set. Event metadata
/// is not a size guarantee. The network stream is limited before SDK decryption.
abstract final class BoundedMatrixMedia {
  static const inlineBytes = 16 * 1024 * 1024;
  // Explicit file downloads, not automatic image previews or browser playback.
  static const fileBytes = 512 * 1024 * 1024;
  static int _active = 0;
  static final _waiting = Queue<Completer<void>>();

  static Future<T> run<T>(Future<T> Function() operation) async {
    if (_active >= 3) {
      if (_waiting.length >= 64) throw StateError('Media loading is busy.');
      final ready = Completer<void>();
      _waiting.add(ready);
      await ready.future;
    } else {
      _active++;
    }
    try {
      return await operation();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  static Future<Uint8List> read(
    Client client,
    Uri uri, {
    int maximumBytes = inlineBytes,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) {
      throw StateError('Media request was cancelled.');
    }
    // Never redirect a bearer token to a media origin or another service.
    if (uri.origin != client.homeserver?.origin ||
        !['https', 'http'].contains(uri.scheme)) {
      throw StateError('Media must be served by your homeserver.');
    }
    final abort = Completer<void>();
    final deadline = Timer(const Duration(seconds: 60), () => abort.complete());
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['authorization'] = 'Bearer ${client.accessToken ?? ''}';
    try {
      final response = await client.httpClient.send(request);
      if (response.statusCode != 200 && response.statusCode != 206 ||
          (response.contentLength ?? 0) > maximumBytes) {
        await response.stream.listen((_) {}).cancel();
        throw StateError('Media is unavailable or exceeds the size limit.');
      }
      return await readBoundedResponse(
        response.stream,
        maximumBytes: maximumBytes,
        isCurrent: isCurrent,
      );
    } finally {
      deadline.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }

  static Future<MatrixFile> attachment(
    Event event, {
    bool thumbnail = false,
    int maximumBytes = inlineBytes,
    bool Function()? isCurrent,
  }) => run(() async {
    if (isCurrent?.call() == false) {
      throw StateError('Media request was cancelled.');
    }
    // The SDK ignores downloadCallback for encrypted scanner downloads. Do
    // not silently use that unbounded path or bypass a configured scanner.
    if (event.room.client.contentScannerConfig != null) {
      throw StateError(
        'Bounded media loading is unavailable with this scanner.',
      );
    }
    final file = await event.downloadAndDecryptAttachment(
      getThumbnail: thumbnail,
      downloadCallback: (uri) => read(
        event.room.client,
        uri,
        maximumBytes: maximumBytes,
        isCurrent: isCurrent,
      ),
    );
    if (file.bytes.length > maximumBytes) {
      throw StateError('Media exceeds the size limit.');
    }
    if (thumbnail ||
        event.type == EventTypes.Sticker ||
        event.messageType == MessageTypes.Image ||
        file.mimeType.startsWith('image/')) {
      await checkImage(file.bytes);
    }
    return file;
  });

  static Future<Uint8List> image(
    Client client,
    Uri mxc, {
    int? width,
    int? height,
    bool crop = true,
    bool animated = true,
    int maximumBytes = inlineBytes,
    bool Function()? isCurrent,
  }) => run(() async {
    if (isCurrent?.call() == false) {
      throw StateError('Media request was cancelled.');
    }
    final uri = width == null
        ? await mxc.getDownloadUri(client)
        : await mxc.getThumbnailUri(
            client,
            width: width,
            height: height,
            method: crop ? ThumbnailMethod.crop : ThumbnailMethod.scale,
            animated: animated,
          );
    final bytes = await read(
      client,
      uri,
      maximumBytes: maximumBytes,
      isCurrent: isCurrent,
    );
    await checkImage(bytes);
    return bytes;
  });

  static Future<void> checkImage(Uint8List bytes) async {
    if (await readEncodedImageDimensions(
          bytes,
          maximumPixels: 32 * 1024 * 1024,
          maximumFramePixels: 256 * 1024 * 1024,
        ) ==
        null) {
      throw StateError('Image dimensions or animation exceed the safe limit.');
    }
  }
}
