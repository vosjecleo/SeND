import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() main) async {
  // A real desktop keyring is not available in the Flutter test shell. Tests
  // exercise encryption using private, in-memory secure-storage plugin data.
  FlutterSecureStorage.setMockInitialValues({});
  await main();
  if (!kIsWeb) {
    // Only widget-test files have a binding. Initialising one globally would
    // replace real HTTP clients in unrelated loopback/integrity tests.
    TestDefaultBinaryMessenger? messenger;
    try {
      messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    } catch (_) {
      return;
    }
    // Each test file gets a private disposable application directory, never the
    // user's real favourites, session or protected cache.
    final directory = await Directory.systemTemp.createTemp(
      'send-test-storage-',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => directory.path,
    );
    tearDownAll(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  }
}
