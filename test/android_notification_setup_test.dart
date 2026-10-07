import 'package:deltiecord/services/unified_push.dart';
import 'package:deltiecord/ui/android_notification_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'widget_test.dart' show FakeBackend;

class _Backend extends FakeBackend {
  String? registered;
  String? removed;
  @override
  Future<void> setUnifiedPushEndpoint(String endpoint) async =>
      registered = endpoint;
  @override
  Future<void> removeUnifiedPushEndpoint(String endpoint) async =>
      removed = endpoint;
}

void main() {
  const channel = MethodChannel('net.deltie.deltiecord/unified_push');
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const endpoint = 'https://push.deltie.net/up-test?up=1';
  final calls = <String>[];
  var disabled = false;
  var permission = true;
  var enabled = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    disabled = false;
    permission = true;
    enabled = false;
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'enableBuiltIn') enabled = true;
          if (call.method == 'unregister') {
            disabled = true;
            enabled = false;
          }
          return <String, Object?>{
            'distributor': enabled ? 'builtin' : null,
            'endpoint': enabled ? endpoint : null,
            'disabled': '$disabled',
            'connection': 'connected',
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, (_) async => permission);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
  });

  testWidgets('built-in setup needs explicit Apply and registers Matrix', (
    tester,
  ) async {
    final backend = _Backend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AndroidNotificationSetup(backend: backend)),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, ['getState']);
    expect(backend.registered, isNull);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(calls, contains('enableBuiltIn'));
    expect(backend.registered, endpoint);
    expect(find.text('Background notifications are on.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('denied permission never starts the listener', (tester) async {
    permission = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AndroidNotificationSetup(backend: _Backend())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('enableBuiltIn')));
    expect(
      find.text('Allow notifications in Android settings, then try again.'),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Off removes registration and disables local transport', (
    tester,
  ) async {
    enabled = true;
    final backend = _Backend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AndroidNotificationSetup(backend: backend)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(backend.removed, endpoint);
    expect(disabled, isTrue);
    expect(calls, contains('unregister'));
    expect(
      await UnifiedPushPlatform.instance.ensureDefaultDistributor(
        '@test:example.org',
      ),
      isFalse,
    );
    expect(calls, isNot(contains('getDistributors')));
    debugDefaultTargetPlatformOverride = null;
  });
}
