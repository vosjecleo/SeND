import 'package:deltiecord/matrix/rtc/rtc_matrix_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class _Database extends Fake implements MatrixSdkDatabase {
  Object failure = StateError('Temporary local read failure');
  int clears = 0;
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => throw failure;
  @override
  Future<void> clear([int? timestamp]) async {
    clears++;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed local initialization retains session and encryption storage',
    () async {
      final database = _Database();
      final client = RtcMatrixClient('initialization-test', database: database);
      final errors = client.onLoginStateChanged.stream.listen(
        (_) {},
        onError: (Object _) {},
      );
      addTearDown(errors.cancel);
      addTearDown(client.dispose);
      await expectLater(client.init(), throwsA(isA<Exception>()));
      expect(database.clears, 0);
      // A second attempt must still read the same store, not a replacement.
      await expectLater(client.init(), throwsA(isA<Exception>()));
      expect(database.clears, 0);
    },
  );
  test(
    'explicit sign-out and genuine token rejection still clear the session',
    () async {
      final database = _Database()
        ..failure = MatrixException.fromJson({'errcode': 'M_UNKNOWN_TOKEN'});
      final client = RtcMatrixClient(
        'revoked-session-test',
        database: database,
      );
      final errors = client.onLoginStateChanged.stream.listen(
        (_) {},
        onError: (Object _) {},
      );
      addTearDown(errors.cancel);
      addTearDown(client.dispose);
      await expectLater(client.init(), throwsA(isA<Exception>()));
      expect(database.clears, 1);
      await client.clear();
      expect(database.clears, 2);
    },
  );
}
