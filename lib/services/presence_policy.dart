import 'package:matrix/matrix.dart';
import '../models/chat_models.dart';

PresenceType clientPresence({
  required bool share,
  required PresenceMode mode,
  required bool idle,
  required bool foreground,
  required bool offlineInBackground,
}) {
  if (!share ||
      mode == PresenceMode.invisible ||
      (offlineInBackground && !foreground)) {
    return PresenceType.offline;
  }
  return switch (mode) {
    PresenceMode.idle => PresenceType.unavailable,
    PresenceMode.online =>
      idle ? PresenceType.unavailable : PresenceType.online,
    PresenceMode.doNotDisturb => PresenceType.online,
    PresenceMode.invisible => PresenceType.offline,
  };
}
