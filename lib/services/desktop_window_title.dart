import '../models/chat_models.dart';
import '../version.dart';

String desktopWindowTitle({RoomSummary? room, String? serverName}) {
  String clean(String value) => String.fromCharCodes(
    value.runes.take(160),
  ).replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
  const app = 'SeND v$deltiecordDisplayVersion';
  if (room == null) return app;
  final name = clean(room.name);
  final server = room.isDirect ? '' : clean(serverName ?? '');
  return '$app | $name${server.isEmpty ? '' : ' - $server'}';
}
