import 'package:flutter/material.dart';

import 'app.dart';
import 'matrix/matrix_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = MatrixBackend();
  runApp(DeltiecordApp(backend: backend));
  await backend.initialize();
}
