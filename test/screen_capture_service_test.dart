import 'package:deltiecord/services/screen_capture_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.deltie.deltiecord/screen_share');
  final calls = <String>[];
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('consent precedes foreground service startup', () async {
    expect(
      await ScreenCaptureService.prepare(
        requestPermission: () async {
          calls.add('consent');
          return true;
        },
      ),
      isTrue,
    );
    expect(calls, ['consent', 'start']);
    await ScreenCaptureService.stop();
    expect(calls.last, 'stop');
  });
  test('refusing capture does not start a service', () async {
    expect(
      await ScreenCaptureService.prepare(requestPermission: () async => false),
      isFalse,
    );
    expect(calls, isEmpty);
  });
  test('desktop capture does not use Android service', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(
      await ScreenCaptureService.prepare(
        requestPermission: () async => throw StateError('must not ask'),
      ),
      isTrue,
    );
    await ScreenCaptureService.stop();
    expect(calls, isEmpty);
  });
}
