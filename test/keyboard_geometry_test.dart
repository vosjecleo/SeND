import 'package:deltiecord/services/keyboard_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only focused, settled geometry is authoritative', () {
    for (final visible in [null, false, true]) {
      for (final focused in [false, true]) {
        for (final animating in [false, true]) {
          final value = KeyboardGeometry(
            visible: visible,
            physicalBottom: 300,
            focused: focused,
            animating: animating,
          );
          expect(value.settled, visible != null && focused && !animating);
        }
      }
    }
    expect(KeyboardGeometry.fromMap({'physicalBottom': double.nan}), isNull);
    expect(KeyboardGeometry.fromMap({'physicalBottom': -1}), isNull);
  });
  test('physical keyboard height respects app scale and hidden state', () {
    const keyboard = KeyboardGeometry(visible: true, physicalBottom: 600);
    expect(keyboard.bottomForView(1800, 900), 300);
    expect(keyboard.bottomForView(1800, 600), 200);
    const closed = KeyboardGeometry(visible: false, physicalBottom: 600);
    expect(closed.bottomForView(1800, 900), 0);
  });
  test('resized browser canvases do not get the same keyboard space twice', () {
    const keyboard = KeyboardGeometry(
      visible: true,
      physicalBottom: 600,
      physicalViewportHeight: 1000,
    );
    expect(keyboard.bottomForView(1600, 800), 300);
    expect(keyboard.bottomForView(1000, 500), 0);
  });
}
