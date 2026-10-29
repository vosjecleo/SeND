import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;

typedef _FileCrypt = ({
  bool decrypt,
  List<int> bytes,
  List<int> key,
  List<int> aad,
});
Future<Uint8List> _cryptFile(_FileCrypt input) async {
  final cipher = AesGcm.with256bits(), key = SecretKey(input.key);
  if (input.decrypt) {
    return Uint8List.fromList(
      await cipher.decrypt(
        SecretBox(
          input.bytes.sublist(33),
          nonce: input.bytes.sublist(5, 17),
          mac: Mac(input.bytes.sublist(17, 33)),
        ),
        secretKey: key,
        aad: input.aad,
      ),
    );
  }
  final box = await cipher.encrypt(input.bytes, secretKey: key, aad: input.aad);
  return Uint8List.fromList([
    ...ProtectedFileCodec._header,
    ...box.nonce,
    ...box.mac.bytes,
    ...box.cipherText,
  ]);
}

Future<Uint8List> _processFile(_FileCrypt input) =>
    input.bytes.length >= 65536 && !kIsWeb
    ? compute(_cryptFile, input, debugLabel: 'protected-file')
    : _cryptFile(input);

/// Versioned framing around the library's authenticated AES-GCM implementation.
/// The key is never saved beside the files. Decrypted buffers are process memory.
class ProtectedFileCodec {
  ProtectedFileCodec({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage storage;
  static const _name = 'send.private_file_key.v1';
  static const _header = <int>[83, 69, 78, 68, 1];
  static final instance = ProtectedFileCodec();
  final _cipher = AesGcm.with256bits();
  Future<SecretKey>? _key;
  bool encrypted(List<int> bytes) =>
      bytes.length >= _header.length &&
      List.generate(
        _header.length,
        (i) => bytes[i] == _header[i],
      ).every((v) => v);
  Future<SecretKey> _loadKey(bool requireExisting) => _key ??=
      () async {
        var value = await storage.read(key: _name);
        if (value == null) {
          if (requireExisting) {
            throw StateError(
              'Protected file key unavailable. Existing files were kept.',
            );
          }
          value = base64UrlEncode(
            await (await _cipher.newSecretKey()).extractBytes(),
          );
          await storage.write(key: _name, value: value);
          if (await storage.read(key: _name) != value) {
            throw StateError('Could not protect the file key.');
          }
        }
        final bytes = base64Url.decode(value);
        if (bytes.length != 32) throw StateError('Invalid protected file key.');
        return SecretKey(bytes);
      }().catchError((Object error) {
        _key = null;
        throw StateError(
          'Protected file key unavailable. Existing files were kept.',
        );
      });

  Future<Uint8List> seal(
    List<int> bytes,
    String purpose, {
    bool requireExisting = false,
  }) async {
    return _processFile((
      decrypt: false,
      bytes: bytes,
      key: await (await _loadKey(requireExisting)).extractBytes(),
      aad: utf8.encode('SeND/$purpose'),
    ));
  }

  Future<Uint8List> open(List<int> bytes, String purpose) async {
    if (!encrypted(bytes) || bytes.length < 33) {
      throw StateError('Invalid protected file.');
    }
    try {
      return await _processFile((
        decrypt: true,
        bytes: bytes,
        key: await (await _loadKey(true)).extractBytes(),
        aad: utf8.encode('SeND/$purpose'),
      ));
    } catch (_) {
      throw StateError(
        'Could not open protected file. Existing files were kept.',
      );
    }
  }
}
