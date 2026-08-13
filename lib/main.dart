import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;

import 'app.dart';
import 'matrix/matrix_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await vodozemac.init();
  final backend = MatrixBackend();
  runApp(DeltiecordApp(backend: backend));
  await backend.initialize();
}
