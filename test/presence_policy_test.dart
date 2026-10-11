import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/presence_policy.dart';

void main() {
  test(
    'background phone/PWA stays offline; desktop focus does not determine idle',
    () {
      PresenceType presence(
        bool backgroundOffline, {
        bool foreground = false,
        bool idle = false,
        bool share = true,
        PresenceMode mode = PresenceMode.online,
      }) => clientPresence(
        share: share,
        mode: mode,
        idle: idle,
        foreground: foreground,
        offlineInBackground: backgroundOffline,
      );
      for (final mode in PresenceMode.values) {
        expect(presence(true, mode: mode), PresenceType.offline);
      }
      expect(presence(false), PresenceType.online);
      expect(presence(false, idle: true), PresenceType.unavailable);
      expect(presence(true, foreground: true), PresenceType.online);
      expect(
        presence(true, foreground: true, share: false),
        PresenceType.offline,
      );
      expect(
        presence(true, foreground: true, mode: PresenceMode.invisible),
        PresenceType.offline,
      );
    },
  );
}
