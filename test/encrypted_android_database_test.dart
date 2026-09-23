import 'dart:io';
import 'package:deltiecord/matrix/encrypted_android_database.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File database;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'deltiecord-cipher-test-',
    );
    database = File('${directory.path}/matrix.db');
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'lost key never replaces an encrypted database or generates a new key',
    () async {
      final original = List<int>.generate(64, (i) => i);
      await database.writeAsBytes(original);
      await expectLater(
        openEncryptedAndroidDatabase(database.path),
        throwsStateError,
      );
      expect(await database.readAsBytes(), original);
      expect(await const FlutterSecureStorage().readAll(), isEmpty);
    },
  );

  test(
    'unavailable cipher plugin leaves the plaintext source intact',
    () async {
      const original = 'SQLite format 3\u0000migration fixture';
      await database.writeAsString(original);
      await expectLater(
        openEncryptedAndroidDatabase(database.path),
        throwsA(anything),
      );
      expect(await database.readAsString(), original);
      final key = await const FlutterSecureStorage().read(
        key: 'deltiecord.matrix_database_key.v1',
      );
      expect(key, matches(r'^[A-Za-z0-9_-]{43}=$'));
    },
  );
}
