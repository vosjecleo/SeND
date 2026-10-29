import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Installation-local, deliberately separate from remote update discovery.
class UpdateNotesStore {
  UpdateNotesStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'send.update_notes.build';

  Future<bool> shouldShow(int build, {required bool existingInstall}) async {
    final previous = int.tryParse(await _storage.read(key: _key) ?? '');
    if (!existingInstall) {
      await acknowledge(build);
      return false;
    }
    // The first release with notes migrates installations that already finished
    // onboarding. Downgrades never announce themselves as a new update.
    return previous == null || previous < build;
  }

  Future<void> acknowledge(int build) async {
    final previous = int.tryParse(await _storage.read(key: _key) ?? '') ?? 0;
    if (build > previous) {
      await _storage.write(key: _key, value: '$build');
    }
  }
}
