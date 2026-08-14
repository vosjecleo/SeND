import 'package:flutter/material.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vodozemac;
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'matrix/matrix_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Matrix only constructs its E2EE engine when Vodozemac is ready first.
  await vodozemac.init();
  final backend = MatrixBackend();
  runApp(DeltiecordApp(backend: backend));
  await backend.initialize();
}
