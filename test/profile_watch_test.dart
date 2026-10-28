import 'package:deltiecord/services/profile_refresh_policy.dart';
import 'package:deltiecord/ui/profile_watch.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

class _Backend extends FakeBackend {
  final visible = <String, bool Function()>{};
  @override
  VoidCallback watchProfile(
    String id, {
    required bool Function() isVisible,
    bool expanded = false,
  }) {
    visible[id] = isVisible;
    return () => visible.remove(id);
  }
}

void main() {
  test('visible profile metadata tiers match the requested schedule', () {
    Duration? interval(
      int rank, {
      bool expanded = false,
      bool checked = true,
    }) => ProfileRefreshPolicy.visibleMetadataInterval(
      homeRank: rank,
      expanded: expanded,
      checkedOnce: checked,
    );
    for (var rank = 0; rank < 5; rank++) {
      expect(interval(rank), const Duration(seconds: 30));
    }
    for (var rank = 5; rank < 10; rank++) {
      expect(interval(rank), const Duration(minutes: 2));
    }
    expect(interval(10), isNull);
    expect(interval(-1), isNull);
    expect(interval(10, checked: false), Duration.zero);
    expect(interval(-1, expanded: true), const Duration(seconds: 30));
  });
  testWidgets(
    'metadata watchers ignore hidden routes and unsubscribe on removal',
    (tester) async {
      final backend = _Backend();
      Widget view(bool enabled) => MaterialApp(
        home: TickerMode(
          enabled: enabled,
          child: Center(
            child: ProfileWatch(
              backend: backend,
              id: '@a:test',
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );
      await tester.pumpWidget(view(true));
      expect(backend.visible['@a:test']!(), true);
      await tester.pumpWidget(view(false));
      expect(backend.visible['@a:test']!(), false);
      await tester.pumpWidget(const SizedBox());
      expect(backend.visible, isEmpty);
    },
  );
}
