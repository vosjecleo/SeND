import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/socks_proxy_config.dart';
import 'package:deltiecord/ui/socks_proxy_settings.dart';

void main() {
  Future<void> open(
    WidgetTester tester, {
    Future<SocksProxyConfig> Function()? load,
    Future<void> Function(SocksProxyConfig)? save,
    Future<void> Function()? reset,
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showSocksProxySettings(
                  context,
                  load: load ?? () async => const SocksProxyConfig(),
                  save: save ?? (_) async {},
                  reset: reset ?? () async {},
                );
              },
              child: const Text('Open proxy'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open proxy'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'proxy dialog saves device settings and warns about direct traffic',
    (tester) async {
      SocksProxyConfig? saved;
      await open(
        tester,
        save: (value) async {
          saved = value;
        },
      );
      expect(find.textContaining('may expose your IP address'), findsOneWidget);
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(switches[1].value, isTrue);
      await tester.tap(find.text('Use SOCKS5 after restart'));
      await tester.enterText(find.byType(TextField).at(0), 'proxy.example.org');
      await tester.enterText(find.byType(TextField).at(1), '9050');
      await tester.enterText(find.byType(TextField).at(2), 'proxy-user');
      await tester.enterText(find.byType(TextField).at(3), 'proxy-password');
      expect(
        tester.widget<TextField>(find.byType(TextField).at(3)).obscureText,
        isTrue,
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved?.enabled, isTrue);
      expect(saved?.host, 'proxy.example.org');
      expect(saved?.port, 9050);
      expect(saved?.password, 'proxy-password');
      expect(saved?.allowDirectTraffic, isTrue);
      expect(find.textContaining('Fully close and reopen'), findsOneWidget);
    },
  );

  testWidgets('invalid settings do not save; damaged settings can be reset', (
    tester,
  ) async {
    var saves = 0, resets = 0;
    await open(
      tester,
      save: (_) async {
        saves++;
      },
    );
    await tester.enterText(find.byType(TextField).at(1), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saves, 0);
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await open(
      tester,
      load: () async => throw const FormatException(),
      reset: () async {
        resets++;
      },
    );
    expect(
      find.textContaining('Could not read the saved proxy'),
      findsOneWidget,
    );
    await tester.tap(find.text('Disable saved proxy'));
    await tester.pumpAndSettle();
    expect(resets, 1);
  });
}
