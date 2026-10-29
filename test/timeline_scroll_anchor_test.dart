import 'package:deltiecord/ui/timeline_scroll_anchor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
