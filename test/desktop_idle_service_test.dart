import 'package:deltiecord/services/desktop_idle_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('net.deltie.deltiecord/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'uses session-wide native duration and a ten-minute threshold',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'idleMilliseconds');
        return 600001;
      });
      expect(
        await DesktopIdleService.elapsed(),
        const Duration(milliseconds: 600001),
      );
      expect(DesktopIdleService.timeout, const Duration(minutes: 10));
    },
  );
  test('unsupported sessions safely fall back to app input', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await DesktopIdleService.elapsed(), isNull);
  });
}
