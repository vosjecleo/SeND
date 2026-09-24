import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/room_event_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('room overrides inherit account defaults and reset independently', () {
    const initial = RoomEventVisibility();
    final global = initial.withValue(null, CosmeticRoomEvent.avatar, false);
    final room = global.withValue('!one', CosmeticRoomEvent.avatar, true);
    expect(initial.visible('!one', CosmeticRoomEvent.avatar), isTrue);
    expect(room.visible('!one', CosmeticRoomEvent.avatar), isTrue);
    expect(room.visible('!two', CosmeticRoomEvent.avatar), isFalse);
    expect(
      room
          .withValue('!one', CosmeticRoomEvent.avatar, null)
          .visible('!one', CosmeticRoomEvent.avatar),
      isFalse,
    );
    expect(RoomEventVisibility.fromJson(room.toJson()).toJson(), room.toJson());
  });
  test('malformed values are ignored and future keys survive round trips', () {
    final settings = RoomEventVisibility.fromJson({
      'defaults': {'avatar': 'false', 'future': false},
      'rooms': {
        '!one': {'name': false},
        '!broken': 1,
      },
    });
    expect(settings.visible('!one', CosmeticRoomEvent.avatar), isTrue);
    expect(settings.visible('!one', CosmeticRoomEvent.name), isFalse);
    expect(settings.toJson()['defaults'], {'future': false});
    expect(RoomEventVisibility.fromJson(null).rooms, isEmpty);
  });
  test('unrelated preference updates retain visibility settings', () {
    final settings = const RoomEventVisibility().withValue(
      '!one',
      CosmeticRoomEvent.name,
      false,
    );
    final prefs = AppPreferences(
      roomEventVisibility: settings,
    ).copyWith(fontScale: 1.2);
    expect(
      prefs.roomEventVisibility.visible('!one', CosmeticRoomEvent.name),
      isFalse,
    );
  });
}
