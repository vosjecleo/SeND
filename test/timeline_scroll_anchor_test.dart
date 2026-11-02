import 'package:deltiecord/ui/timeline_scroll_anchor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a retained event anchor restores only in its original segment', (
    tester,
  ) async {
    final viewport = GlobalKey(), scroll = ScrollController();
    final keys = <String, GlobalKey>{};
    final ids = List.generate(30, (i) => 'old$i');
    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              key: viewport,
              height: 400,
              child: SingleChildScrollView(
                controller: scroll,
                reverse: true,
                child: Column(
                  children: [
                    for (final id in ids.reversed)
                      SizedBox(
                        key: keys.putIfAbsent(id, GlobalKey.new),
                        height: 40,
                        child: Text(id),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await show();
    scroll.jumpTo(200);
    await tester.pump();
    final anchor = captureSegmentTimelineAnchor(viewport, keys, 'history')!;
    ids.insertAll(0, List.generate(10, (i) => 'new$i'));
    await show();
    final before = scroll.offset;
    restoreSegmentTimelineAnchor(scroll, keys, anchor, 'live');
    expect(scroll.offset, before);
    restoreSegmentTimelineAnchor(scroll, keys, anchor, 'history');
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(keys[anchor.position.$1]!)).dy,
      closeTo(anchor.position.$2, .01),
    );
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  testWidgets(
    'shared navigation reveals lazy variable-height rows in both directions',
    (tester) async {
      final scroll = ScrollController(), keys = <String, GlobalKey>{};
      final ids = List.generate(90, (i) => 'row$i');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ListView.builder(
                controller: scroll,
                reverse: true,
                itemCount: ids.length,
                itemBuilder: (_, i) => SizedBox(
                  key: keys.putIfAbsent(ids[i], GlobalKey.new),
                  height: 40 + (i % 7) * 12,
                  child: Text(ids[i]),
                ),
              ),
            ),
          ),
        ),
      );
      for (final target in ['row72', 'row3']) {
        final navigation = scrollToTimelineRow(
          controller: scroll,
          rowKeys: keys,
          ids: ids,
          id: target,
          isCurrent: () => true,
          reducedMotion: true,
        );
        await tester.pumpAndSettle();
        expect(await navigation, true);
        expect(tester.getRect(find.text(target)).top, greaterThanOrEqualTo(0));
        expect(
          tester.getRect(find.text(target)).bottom,
          lessThanOrEqualTo(400),
        );
      }
      final offset = scroll.offset;
      expect(
        await scrollToTimelineRow(
          controller: scroll,
          rowKeys: keys,
          ids: ids,
          id: 'row80',
          isCurrent: () => false,
        ),
        false,
      );
      expect(scroll.offset, offset);
      await tester.pumpWidget(const SizedBox.shrink());
      scroll.dispose();
    },
  );
}
