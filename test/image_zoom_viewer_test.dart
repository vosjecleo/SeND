import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/ui/image_zoom_viewer.dart';

void main() {
  testWidgets('double tap zooms at the tap point, second double tap resets', (
    tester,
  ) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    var holds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 400,
            child: ImageZoomViewer(
              transformationController: controller,
              child: GestureDetector(
                onLongPress: () => holds++,
                behavior: HitTestBehavior.opaque,
                child: const Center(child: Text('Image')),
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(ImageZoomViewer));
    final point = origin + const Offset(90, 120);
    Future<void> twice() async {
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
    }

    await twice();
    expect(controller.value.getMaxScaleOnAxis(), 2.5);
    expect(controller.value.entry(0, 3), -135);
    expect(controller.value.entry(1, 3), -180);
    expect(holds, 0);
    await twice();
    expect(controller.value, Matrix4.identity());
    await tester.longPressAt(point);
    await tester.pumpAndSettle();
    expect(holds, 1);
    expect(controller.value, Matrix4.identity());
    await tester.pumpWidget(const SizedBox());
    controller.value = Matrix4.identity(); // Borrowed controller not disposed.
  });
}
