import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/private_file_store.dart';
import 'package:deltiecord/services/protected_file_codec.dart';

void main() {
  test(
    'large cache buffers round-trip through background file crypto',
    () async {
      final bytes = List<int>.generate(200000, (i) => i % 251);
      final codec = ProtectedFileCodec();
      final sealed = await codec.seal(bytes, 'cache');
      expect(await codec.open(sealed, 'cache'), bytes);
    },
  );
  test(
    'interrupted private-file replacement recovers its original path',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'send-private-recovery-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/drafts.json');
      await writePrivateTextFile(file, 'kept');
      await file.rename('${file.path}.send-replacement-backup');
      expect(await privateFileExists(file), true);
      expect(await readPrivateTextFile(file), 'kept');
      expect(
        await File('${file.path}.send-replacement-backup').exists(),
        false,
      );
    },
  );
  test(
    'private files are authenticated ciphertext, legacy JSON migrates atomically',
    () async {
      final folder = await Directory.systemTemp.createTemp('send-private-');
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/drafts.json');
      await file.writeAsString('{"message":"private words"}');
      expect(await readPrivateTextFile(file), '{"message":"private words"}');
      final raw = await file.readAsBytes();
      expect(ProtectedFileCodec.instance.encrypted(raw), true);
      expect(latin1.decode(raw), isNot(contains('private words')));
      final fresh = ProtectedFileCodec();
      expect(
        utf8.decode(await fresh.open(raw, 'drafts.json')),
        '{"message":"private words"}',
      );
      await expectLater(fresh.open(raw, 'another-file'), throwsStateError);
      final damaged = List<int>.of(raw)..[raw.length - 1] ^= 1;
      await expectLater(fresh.open(damaged, 'drafts.json'), throwsStateError);
    },
  );
  test('missing file keys cannot silently replace encrypted content', () async {
    const storage = FlutterSecureStorage();
    final codec = ProtectedFileCodec();
    final raw = await codec.seal(utf8.encode('kept'), 'kept');
    final saved = await storage.readAll();
    try {
      await storage.deleteAll();
      final fresh = ProtectedFileCodec();
      await expectLater(fresh.open(raw, 'kept'), throwsStateError);
      await expectLater(
        fresh.seal(utf8.encode('replacement'), 'kept', requireExisting: true),
        throwsStateError,
      );
    } finally {
      for (final entry in saved.entries) {
        await storage.write(key: entry.key, value: entry.value);
      }
    }
  });
  test(
    'explicit deletion also removes an interrupted replacement backup',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'send-private-clear-',
      );
      addTearDown(() => folder.delete(recursive: true));
      final file = File('${folder.path}/drafts.json');
      await writePrivateTextFile(file, 'kept');
      await file.copy('${file.path}.send-replacement-backup');
      await deletePrivateFile(file);
      expect(await privateFileExists(file), false);
    },
  );
}
