import 'package:matrix/matrix.dart';

bool rtcUserStillJoined(Room room, String userId) {
  if (room.membership != Membership.join) return false;
  final membership = room
      .getState(EventTypes.RoomMember, userId)
      ?.content['membership'];
  // Lazy-loading may omit unchanged member state. A valid RTC event already
  // passed room authorization, but a later leave/ban immediately revokes it.
  return membership == null || membership == 'join';
}
