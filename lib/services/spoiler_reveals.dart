import '../backend/chat_backend.dart';
import '../models/chat_models.dart';

/// Session-only UI state, independent of recycled timeline widgets. Never saved.
class SpoilerReveals {
  static final _sessions = Expando<SpoilerReveals>();
  static SpoilerReveals forBackend(ChatBackend backend) =>
      _sessions[backend] ??= SpoilerReveals._(backend);
  SpoilerReveals._(ChatBackend backend) {
    backend.addListener(() {
      if (backend.status != SessionStatus.signedIn) _ids.clear();
    });
  }
  final Set<String> _ids = {};
  bool contains(String id) => _ids.contains(id);
  void reveal(String id) {
    if (_ids.length >= 1024) _ids.remove(_ids.first);
    _ids.add(id);
  }
}
