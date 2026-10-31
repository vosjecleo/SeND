import 'package:deltiecord/matrix/rtc/rtc_room_membership.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'support/rtc_wire_fixture.dart' show wireClient, jsonResponse;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('room leaves and bans revoke an otherwise live RTC lease', () async {
    final client = await wireClient((_) async => jsonResponse({}));
    addTearDown(client.dispose);
    final room = Room(id: '!call:example.org', client: client);
    const user = '@friend:example.org';
    expect(rtcUserStillJoined(room, user), isTrue);
    for (final membership in ['join', 'leave', 'ban', 'invite', 'knock']) {
      room.states[EventTypes.RoomMember] = {
        user: User(user, room: room, membership: membership),
      };
      expect(rtcUserStillJoined(room, user), membership == 'join');
    }
  });
  test('leaving the local room revokes every call participant', () async {
    final client = await wireClient((_) async => jsonResponse({}));
    addTearDown(client.dispose);
    final room = Room(
      id: '!call:example.org',
      client: client,
      membership: Membership.leave,
    );
    expect(rtcUserStillJoined(room, '@friend:example.org'), isFalse);
  });
}
