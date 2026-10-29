import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../matrix/encrypted_android_database.dart';
import '../matrix/encrypted_desktop_database.dart';
import 'private_file_store.dart';
import 'history_index_sql.dart';

bool get historyIndexEncryptedAtRest =>
    Platform.isAndroid ||
    Platform.isLinux ||
    Platform.isWindows ||
    Platform.isMacOS;

class HistoryStore extends HistorySqlStore {
  HistoryStore(super.account, {super.database});
  @override
  String failureCode(Object error) {
    if (error is FileSystemException) {
      return 'FILE_${error.osError?.errorCode ?? 0}';
    }
    if (error is StateError) {
      final code = RegExp(
        r'SQLITE_[0-9]+',
      ).firstMatch(error.message.toString());
      if (code != null) return code.group(0)!;
    }
    return super.failureCode(error);
  }

  @override
  Future<void> open() async {
    if (database == null) {
      final folder = Directory(
        '${(await getApplicationSupportDirectory()).path}/deltiecord/search',
      );
      await ensurePrivateDirectory(folder);
      final path = '${folder.path}/$account.db';
      openStage = 'database';
      if (Platform.isAndroid) {
        database = await openEncryptedAndroidDatabase(path);
      } else {
        database = await openEncryptedDesktopDatabase(path);
      }
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('chmod', ['600', path]);
      }
    }
    await super.open();
  }
}
