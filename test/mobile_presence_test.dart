import 'dart:async';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/mobile_presence_publisher.dart';
import 'package:deltiecord/ui/avatar_presence.dart';
import 'package:deltiecord/ui/activity_widgets.dart';
import 'package:deltiecord/ui/mobile/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _MobileBackend extends FakeBackend {
  @override
  bool mobileOnlineFor(String userId) => userId == '@phone:test';
}

void main() {
  test('phone cutout leaves no avatar sliver to its right', () {
    final cutout = AvatarPresenceCutout(
      badgeSize: presenceBadgeSize(98 * .27, phone: true),
      phone: true,
    );
    final path = cutout.getClip(const Size.square(98));
    // This point is inside the circular avatar, just beyond the old hole.
    expect(path.contains(const Offset(96, 59)), isFalse);
    expect(path.contains(const Offset(49, 49)), isTrue);
  });
  test(
    'phone badge keeps its approved size; round statuses use the midpoint',
    () {
      expect(presenceBadgeSize(11, phone: true), 16.5);
      expect(presenceBadgeSize(11), 13.75);
    },
  );
  testWidgets(
    'desktop/profile avatar badge scales up and clamps to its square bounds',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox.square(
              dimension: 40,
              child: AvatarPresence(
                presence: UserPresence.online,
                userId: null,
                badgeSize: 11,
                right: -1,
                bottom: -1,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );
      final avatar = tester.getRect(find.byType(AvatarPresence));
      final badge = tester.getRect(find.byType(PresenceBadge));
      expect(badge.size, const Size.square(13.75));
      expect(badge.right, avatar.right);
      expect(badge.bottom, avatar.bottom);
      expect(badge.left, greaterThan(avatar.left));
      expect(badge.top, greaterThan(avatar.top));
    },
  );
  testWidgets('mobile presence opt-out belongs to Privacy', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await openSettingsSection(tester, 'Privacy');
    final setting = find.widgetWithText(
      SwitchListTile,
      'Show when I’m on mobile',
    );
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    await tester.tap(setting);
    await tester.pumpAndSettle();
    expect(backend.preferences.shareMobilePresence, isFalse);
    expect(backend.preferences.sharePresence, isTrue);
    await tester.pumpWidget(const SizedBox());
    backend.dispose();
  });
  test('mobile presence is opt-out and survives preference copies', () {
    const defaults = AppPreferences();
    expect(defaults.shareMobilePresence, isTrue);
    expect(
      defaults
          .copyWith(shareMobilePresence: false)
          .copyWith(sharePresence: true)
          .shareMobilePresence,
      isFalse,
    );
  });
  test(
    'phone publication renews, clears in background, and respects opt-out',
    () async {
      var enabled = true;
      var now = DateTime.now();
      final writes = <Map<String, Object?>?>[];
      final publisher = MobilePresencePublisher(
        enabled: () => enabled,
        now: () => now,
        write: (value) async => writes.add(value),
      );
      addTearDown(publisher.close);
      await publisher.refresh();
      expect(writes.single, {
        'version': 1,
        'mobile': true,
        'expires_at': now
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
      });
      expect(publisher.active, isTrue);
      now = now.add(const Duration(seconds: 50));
      await publisher.refresh();
      expect(writes.length, 1);
      now = now.add(const Duration(seconds: 6));
      await publisher.refresh();
      expect(writes.length, 2);
      enabled = false;
      expect(publisher.active, isFalse);
      await publisher.refresh();
      expect(writes.last, isNull);
      await publisher.refresh();
      expect(writes.length, 3);
    },
  );
  test(
    'disabling while a publication is in flight clears the same device',
    () async {
      var enabled = true;
      final gate = Completer<void>();
      final writes = <Map<String, Object?>?>[];
      final publisher = MobilePresencePublisher(
        enabled: () => enabled,
        write: (value) async {
          writes.add(value);
          if (value != null) await gate.future;
        },
      );
      addTearDown(publisher.close);
      final first = publisher.refresh();
      enabled = false;
      unawaited(publisher.refresh());
      gate.complete();
      await first;
      await publisher.refresh();
      expect(writes.length, 2);
      expect(writes.last, isNull);
      expect(publisher.active, isFalse);
    },
  );
  test(
    'failed publication backs off instead of polling the server repeatedly',
    () async {
      var time = DateTime.now();
      var attempts = 0;
      final publisher = MobilePresencePublisher(
        enabled: () => true,
        now: () => time,
        write: (_) async {
          attempts++;
          throw StateError('offline');
        },
      );
      addTearDown(publisher.close);
      await publisher.refresh();
      for (var i = 0; i < 5; i++) {
        await publisher.refresh();
      }
      expect(attempts, 1);
      expect(publisher.active, isFalse);
      time = time.add(const Duration(seconds: 31));
      await publisher.refresh();
      expect(attempts, 2);
    },
  );
  test(
    'device fields are independent and stale or malformed signals are ignored',
    () {
      final now = DateTime.now();
      final valid = {
        'version': 1,
        'mobile': true,
        'expires_at': now
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
      };
      final first = mobilePresenceField('phone-a'),
          second = mobilePresenceField('phone-b');
      expect(first, isNot(second));
      expect(first, isNot(contains('phone-a')));
      expect(
        UserActivities.fromRecords({first: valid, second: null}).mobileOnline,
        isTrue,
      );
      for (final record in [
        null,
        {...valid, 'mobile': false},
        {...valid, 'version': 2},
        {
          ...valid,
          'expires_at': now
              .subtract(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        },
        {
          ...valid,
          'expires_at': now
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        },
      ]) {
        expect(
          UserActivities.fromRecords({first: record}).mobileOnline,
          isFalse,
        );
      }
      expect(
        UserActivities.fromRecords({activityProfileField: valid}).mobileOnline,
        isFalse,
      );
    },
  );
  test(
    'phone cutout removes avatar pixels behind the badge but retains the face',
    () {
      final path = const PhonePresenceCutout(
        badgeSize: 12,
      ).getClip(const Size(44, 44));
      expect(path.contains(const Offset(22, 22)), isTrue);
      expect(path.contains(const Offset(39, 39)), isFalse);
      expect(path.contains(const Offset(31, 39)), isTrue);
    },
  );
  for (final presence in UserPresence.values) {
    testWidgets('phone shape is only used while online: ${presence.name}', (
      tester,
    ) async {
      final backend = _MobileBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: ActivityScope(
            backend: backend,
            child: Center(
              child: MobileAvatar(
                key: const ValueKey('presence-test-avatar'),
                bytes: null,
                fallback: 'Phone',
                userId: '@phone:test',
                presence: presence,
              ),
            ),
          ),
        ),
      );
      final badge = tester.widget<PresenceBadge>(find.byType(PresenceBadge));
      expect(badge.phone, presence == UserPresence.online);
      expect(
        badge.size,
        closeTo(
          44 * .27 * (presence == UserPresence.online ? 1.5 : 1.25),
          .001,
        ),
      );
      final avatarBounds = tester.getRect(
        find.byKey(const ValueKey('presence-test-avatar')),
      );
      final badgeBounds = tester.getRect(find.byType(PresenceBadge));
      expect(badgeBounds.left, greaterThanOrEqualTo(avatarBounds.left));
      expect(badgeBounds.top, greaterThanOrEqualTo(avatarBounds.top));
      expect(badgeBounds.right, lessThanOrEqualTo(avatarBounds.right));
      expect(badgeBounds.bottom, lessThanOrEqualTo(avatarBounds.bottom));
      if (presence == UserPresence.offline) {
        final colors = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(PresenceBadge),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((box) => (box.decoration as BoxDecoration).color);
        expect(
          colors,
          containsAll([const Color(0xff70737d), const Color(0xff303238)]),
        );
      }
      if (!badge.phone) {
        final face = tester.getRect(
          find
              .descendant(
                of: find.byType(PresenceBadge),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(face.width, closeTo(badgeBounds.width * .9, .001));
        expect(face.height, closeTo(badgeBounds.height * .9, .001));
        expect(face.center, badgeBounds.center);
      }
      final clips = tester.widgetList<ClipPath>(find.byType(ClipPath));
      expect(
        clips.any(
          (clip) =>
              clip.clipper is AvatarPresenceCutout &&
              (clip.clipper as AvatarPresenceCutout).phone,
        ),
        presence == UserPresence.online,
      );
      await tester.pumpWidget(const SizedBox());
      backend.dispose();
    });
  }
}
