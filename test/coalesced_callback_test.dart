import 'package:deltiecord/services/coalesced_callback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('1000 recovery updates publish latest state once', (
    tester,
  ) async {
    var state = 0;
    final published = <int>[];
    final updates = CoalescedCallback(
      () => published.add(state),
      enabled: true,
    );
    for (var i = 0; i < 1000; i++) {
      state++;
      updates.request();
    }
    expect(published, isEmpty);
    await tester.pump(const Duration(milliseconds: 16));
    expect(published, [1000]);
    updates.request();
    await tester.pump(const Duration(milliseconds: 16));
    expect(published, [1000, 1000]);
    updates.dispose();
  });
  testWidgets('dispose cancels pending callbacks and future requests', (
    tester,
  ) async {
    var calls = 0;
    final updates = CoalescedCallback(() => calls++, enabled: true);
    updates.request();
    updates.dispose();
    updates.request();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });
  test('native notifications remain synchronous', () {
    var calls = 0;
    final updates = CoalescedCallback(() => calls++, enabled: false);
    updates.request();
    updates.request();
    expect(calls, 2);
    updates.dispose();
  });
}
