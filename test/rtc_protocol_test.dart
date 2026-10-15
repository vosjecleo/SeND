import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/matrix/rtc/rtc_protocol.dart';

void main() {
  final now = DateTime.utc(2026, 10, 13);
  final focus = RtcTransport(
    serviceUrl: Uri.parse('https://rtc.example.org/jwt'),
  );

  test(
    'transport discovery accepts current, transitional and legacy formats',
    () {
      for (final key in [
        'transports',
        'rtc_transports',
        'org.matrix.msc4143.rtc_foci',
      ]) {
        final value = RtcTransport.fromResponse({
          key: [
            {'type': 'livekit', 'url': 'wss://sfu.example.org'},
            {
              'type': 'livekit',
              'livekit_service_url': 'https://rtc.example.org/jwt',
            },
            {
              'type': 'm.livekit',
              'url': 'wss://sfu.example.org',
              'livekit_service_url': 'https://rtc.example.org/jwt',
            },
            {'type': 'mesh'},
          ],
        });
        expect(value, hasLength(3));
        expect(value.last.toJson()['type'], 'livekit');
      }
    },
  );

  test(
    'transport URLs reject plaintext, credentials and malformed optional fields',
    () {
      for (final url in [
        'http://rtc.example.org',
        'https://user:password@rtc.example.org',
        'https://rtc.example.org?token=secret',
        'https://rtc.example.org/#fragment',
        'file:///rtc',
      ]) {
        expect(
          RtcTransport.fromJson({
            'type': 'livekit',
            'livekit_service_url': url,
          }),
          isNull,
        );
      }
      expect(
        RtcTransport.fromJson({
          'type': 'livekit',
          'url': 'ws://sfu.example.org',
          'livekit_service_url': 'https://rtc.example.org',
        }),
        isNull,
      );
      expect(
        RtcTransport.fromResponse({
          'transports': List.generate(20, (_) => focus.toJson()),
        }),
        hasLength(8),
      );
    },
  );

  test('participant identity matches MSC4195 canonical JSON hash vector', () {
    expect(
      rtcHashedIdentity('@alice:example.com', 'memberABC'),
      'M3VnsLXrkbxIDINXO64u8PZzFyD9ZYFiQULR2dshWYs',
    );
    expect(
      rtcHashedIdentity('@alice:example.com', 'a:b'),
      isNot(rtcHashedIdentity('@alice:example.com:a', 'b')),
    );
    expect(
      rtcMembershipStateKey('@alice:example.com', 'DEVICE'),
      '_@alice:example.com_DEVICE_m.call',
    );
  });

  test(
    'state membership uses multi-SFU, bounded lifetime and device identity',
    () {
      final content = rtcStateMembership(
        userId: '@alice:example.com',
        deviceId: 'DEVICE',
        createdAt: now,
        transport: focus,
      );
      final member = RtcMember.parse(
        type: rtcCallMemberType,
        sender: '@alice:example.com',
        content: content,
        stateKey: rtcMembershipStateKey('@alice:example.com', 'DEVICE'),
        timestamp: now,
        now: now,
      );
      expect(member?.deviceIdentity, '@alice:example.com:DEVICE');
      expect(member?.backendIdentities, ['@alice:example.com:DEVICE']);
      expect(content['focus_active'], {
        'type': 'livekit',
        'focus_selection': 'multi_sfu',
      });
      expect(content.containsKey('memberships'), isFalse);
      expect(
        RtcMember.parse(
          type: rtcCallMemberType,
          sender: '@alice:example.com',
          content: content,
          stateKey: rtcMembershipStateKey('@alice:example.com', 'DEVICE'),
          timestamp: now,
          now: now.add(const Duration(minutes: 3)),
        ),
        isNull,
      );
      for (final replacement in [
        {'application': 'm.board'},
        {'scope': 'm.user'},
        {'expires': 0},
        {'expires': 86400000},
        {'created_ts': now.add(const Duration(days: 1)).millisecondsSinceEpoch},
      ]) {
        expect(
          RtcMember.parse(
            type: rtcCallMemberType,
            sender: '@alice:example.com',
            content: {...content, ...replacement},
            stateKey: rtcMembershipStateKey('@alice:example.com', 'DEVICE'),
            timestamp: now,
            now: now,
          ),
          isNull,
        );
      }
    },
  );

  test('state slots cannot claim a different user or device', () {
    final content = rtcStateMembership(
      userId: '@alice:example.com',
      deviceId: 'DEVICE',
      createdAt: now,
      transport: focus,
    );
    for (final key in [
      null,
      rtcMembershipStateKey('@bob:example.com', 'DEVICE'),
      rtcMembershipStateKey('@alice:example.com', 'OTHER'),
    ]) {
      expect(
        RtcMember.parse(
          type: rtcCallMemberType,
          sender: '@alice:example.com',
          content: content,
          stateKey: key,
          timestamp: now,
          now: now,
        ),
        isNull,
      );
    }
    for (final key in [
      '_@alice:example.com_DEVICE',
      '@alice:example.com_DEVICE',
    ]) {
      expect(
        RtcMember.parse(
          type: rtcCallMemberType,
          sender: '@alice:example.com',
          content: content,
          stateKey: key,
          timestamp: now,
          now: now,
        ),
        isNotNull,
      );
    }
  });

  test(
    'sticky membership requires authoritative expiry and binds sender to member',
    () {
      final content = rtcStickyMembership(
        userId: '@alice:example.com',
        deviceId: 'DEVICE',
        memberId: 'new-session',
        transport: RtcTransport(url: Uri.parse('wss://sfu.example.com')),
      );
      final member = RtcMember.parse(
        type: rtcStickyMemberType,
        sender: '@alice:example.com',
        content: content,
        timestamp: now,
        now: now,
        stickyExpiresAt: now.add(const Duration(minutes: 1)),
      );
      expect(member?.memberId, 'new-session');
      expect(member?.backendIdentities, [
        rtcHashedIdentity('@alice:example.com', 'new-session'),
      ]);
      expect(
        RtcMember.parse(
          type: rtcStickyMemberType,
          sender: '@bob:example.com',
          content: content,
          timestamp: now,
          now: now,
          stickyExpiresAt: now.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
      expect(
        RtcMember.parse(
          type: rtcStickyMemberType,
          sender: '@alice:example.com',
          content: content,
          timestamp: now,
          now: now,
        ),
        isNull,
      );
      expect(
        RtcMember.parse(
          type: rtcStickyMemberType,
          sender: '@alice:example.com',
          content: rtcStickyMembership(
            userId: '@alice:example.com',
            deviceId: 'DEVICE',
            memberId: 'new-session',
            transport: focus,
            leave: true,
          ),
          timestamp: now,
          now: now,
          stickyExpiresAt: now.add(const Duration(minutes: 1)),
        ),
        isNull,
      );
    },
  );
}
