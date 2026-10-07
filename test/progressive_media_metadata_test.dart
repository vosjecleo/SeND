import 'dart:typed_data';

import 'package:deltiecord/matrix/sized_matrix_file.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('GIF dimensions travel in standard Matrix info without decoding', () {
    final file = SizedMatrixFile(
      bytes: Uint8List.fromList([71, 73, 70]),
      name: 'animation.gif',
      mimeType: 'image/gif',
      width: 320,
      height: 180,
    );
    expect(file.msgType, 'm.image');
    expect(file.info, {'mimetype': 'image/gif', 'size': 3, 'w': 320, 'h': 180});
  });

  test('missing dimensions are not published as a partial pair', () {
    final file = SizedMatrixFile(
      bytes: Uint8List(0),
      name: 'animation.gif',
      mimeType: 'image/gif',
      width: 320,
      height: null,
    );
    expect(file.info.containsKey('w'), isFalse);
    expect(file.info.containsKey('h'), isFalse);
  });

  test(
    'progressive profile media preserves presence, fields and other images',
    () {
      final avatar = Uint8List.fromList([1]);
      final banner = Uint8List.fromList([2]);
      final initial = UserProfileSummary(
        userId: '@test:example.org',
        displayName: 'Test',
        presence: UserPresence.away,
        statusMessage: 'Busy',
        bio: 'Bio',
        pronouns: 'they/them',
        timezone: 'Europe/Amsterdam',
        profileColor: 1,
        profileColorSecondary: 2,
        voiceColor: 3,
        blocked: true,
        extensibleFieldsSupported: false,
        serverRoleNames: const ['Mod'],
      );
      final updated = initial
          .withMedia(avatar: avatar)
          .withMedia(banner: banner);
      expect(updated.avatarBytes, same(avatar));
      expect(updated.bannerBytes, same(banner));
      expect(updated.presence, UserPresence.away);
      expect(updated.statusMessage, 'Busy');
      expect(updated.bio, initial.bio);
      expect(updated.pronouns, initial.pronouns);
      expect(updated.timezone, initial.timezone);
      expect(updated.serverRoleNames, initial.serverRoleNames);
      expect(updated.blocked, isTrue);
      expect(updated.extensibleFieldsSupported, isFalse);
      expect(updated.profileColor, 1);
      expect(updated.profileColorSecondary, 2);
      expect(updated.voiceColor, 3);
    },
  );
}
