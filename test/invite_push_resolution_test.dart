import 'package:deltiecord/services/android_push_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

class InviteClient extends Fake implements Client {
  final Room room;
  InviteClient(this.room);
  @override
  bool isLogged() => true;
  @override
  Future<void> oneShotSync({Duration? timeout}) async {}
  @override
  Room? getRoomById(String roomId) => room;
  @override
  String get userID => '@test:example.org';
  @override
  String get deviceID => 'TEST';
  @override
  Map<String, BasicEvent> get accountData => {};
  @override
  Future<Map<String, Object?>> getAccountData(
    String userId,
    String type,
  ) async => {};
}

class InvitedRoom extends Fake implements Room {
  @override
  final Membership membership;
  InvitedRoom(this.membership);
  @override
  String get id => '!invite:example.org';
  @override
  String getLocalizedDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => 'Invitation';
  // Fetching history, decrypting, or accessing unread counters fails the test:
  // an invited member is not entitled to joined-room history.
}

void main() {
  test(
    'authenticated pending invite resolves without history or unread count',
    () async {
      final result = await resolveAndroidPushNotification(
        InviteClient(InvitedRoom(Membership.invite)),
        '!invite:example.org',
        r'$event',
      );
      expect(result?['unreadCount'], 1);
      expect(result?['eventId'], r'$event');
      expect(result?['resolutionStatus'], isNull);
    },
  );
  test('stale push cannot turn a left room into an invitation', () async {
    final result = await resolveAndroidPushNotification(
      InviteClient(InvitedRoom(Membership.leave)),
      '!invite:example.org',
      r'$event',
    );
    expect(result?['resolutionStatus'], 'event_unavailable');
  });
}
