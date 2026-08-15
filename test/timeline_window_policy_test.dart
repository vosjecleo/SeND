import 'package:deltiecord/services/timeline_window_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hard cap honors preferences but never exceeds 120', () {
    expect(TimelineWindowPolicy.hardCap(chunkSize: 30, chunkCap: 3), 90);
    expect(TimelineWindowPolicy.hardCap(chunkSize: 50, chunkCap: 9), 120);
  });

  test('loading older retains the oldest side of a newest-first window', () {
    final events = List.generate(150, (index) => index);
    TimelineWindowPolicy.trimNewestFirst(
      events,
      hardCap: 120,
      loaded: TimelinePageDirection.older,
    );
    expect(events, List.generate(120, (index) => index + 30));
  });

  test('loading newer retains the newest side of a newest-first window', () {
    final events = List.generate(150, (index) => index);
    TimelineWindowPolicy.trimNewestFirst(
      events,
      hardCap: 120,
      loaded: TimelinePageDirection.newer,
    );
    expect(events, List.generate(120, (index) => index));
  });
}
