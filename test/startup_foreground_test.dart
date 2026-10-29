import 'package:deltiecord/matrix/matrix_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foreground changes before client initialization do not start timeline sync',
    () async {
      final backend = MatrixBackend();
      backend.setApplicationForeground(false);
      backend.setApplicationForeground(true);
      backend.setApplicationForeground(false);
      backend.setApplicationForeground(true);
      await Future<void>.delayed(Duration.zero);
      backend.dispose();
    },
  );
}
