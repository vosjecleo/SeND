import 'package:deltiecord/ui/scaled_media.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safe areas merge without double padding and follow UI scale', () {
    final media = scaledAppMedia(
      const MediaQueryData(
        size: Size(390, 844),
        viewPadding: EdgeInsets.only(top: 47, bottom: 34),
        padding: EdgeInsets.only(top: 47, bottom: 34),
      ),
      1.25,
      const EdgeInsets.only(top: 47, bottom: 34),
    );
    expect(media.padding.bottom, 34 / 1.25);
    expect(media.padding.top, 47 / 1.25);
    expect(media.size, const Size(312, 675.2));
  });
  test(
    'PWA CSS safe area fills missing metrics but disappears above keyboard',
    () {
      const css = EdgeInsets.only(bottom: 34);
      expect(scaledAppMedia(const MediaQueryData(), 1, css).padding.bottom, 34);
      final keyboard = scaledAppMedia(
        const MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
        1,
        css,
      );
      expect(keyboard.padding.bottom, 0);
      expect(keyboard.viewPadding.bottom, 34);
      expect(keyboard.viewInsets.bottom, 300);
      expect(
        scaledAppMedia(const MediaQueryData(), 1, EdgeInsets.zero).padding,
        EdgeInsets.zero,
      );
    },
  );
}
