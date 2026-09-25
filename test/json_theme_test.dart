import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/services/device_appearance_store.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:deltiecord/ui/json_theme.dart';
import 'package:deltiecord/ui/json_theme_settings.dart';
import 'widget_test.dart' show FakeBackend;

class _UnreadSpaceBackend extends FakeBackend {
  @override
  bool hasUnreadForSpace(String spaceId) => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('custom icon packs reject remote, oversized and invalid images', () {
    final bytes = File(
      'assets/icons/tango/actions-list-add.png',
    ).readAsBytesSync();
    final icons = parseThemeIcons({
      'add': 'data:image/png;base64,${base64Encode(bytes)}',
      'home': 'https://example.org/icon.png',
      'search': 'data:image/png;base64,bad',
    });
    expect(icons.keys, ['add']);
    final oversized = Uint8List.fromList(bytes);
    ByteData.sublistView(oversized).setUint32(16, 200000);
    expect(
      parseThemeIcons({
        'add': 'data:image/png;base64,${base64Encode(oversized)}',
      }),
      isEmpty,
    );
  });
  testWidgets(
    'unread server dot becomes the selected bar without requiring pings',
    (tester) async {
      final backend = _UnreadSpaceBackend()
        ..currentStatus = SessionStatus.signedIn
        ..spaceList = const [
          SpaceSummary(id: '!space:example.org', name: 'Unread server'),
        ];
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-marker-Unread server')),
        findsOneWidget,
      );
      expect(backend.pingCountForSpace('!space:example.org'), 0);
      await tester.tap(find.byTooltip('Unread server'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('space-marker-Unread server')),
        findsOneWidget,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('space-marker-Unread server')))
            .height,
        24,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      backend.dispose();
    },
  );
  testWidgets(
    'glass avatar keeps dimensions and default avatars stay circular',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: ThemeAvatar(radius: 20, child: Text('A'))),
        ),
      );
      expect(find.byType(CircleAvatar), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [ThemeChrome(glassAvatars: true)]),
          home: const Center(child: ThemeAvatar(radius: 20, child: Text('A'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNothing);
      expect(tester.getSize(find.byType(ThemeAvatar)), const Size(40, 40));
      expect(tester.takeException(), isNull);
    },
  );
  test('component styling is bounded and honours accessibility', () {
    final theme = JsonTheme.parse(
      jsonEncode({
        'schema': 1,
        'id': 'glass.test',
        'name': 'Glass',
        'surfaces': {
          'popup': {
            'gradient': List.filled(20, '#FFFFFF'),
            'opacity': 0,
            'blur': 100,
            'texture': 1,
            'shadow': 2,
            'transitionMs': 10000,
            'gloss': 5,
          },
        },
      }),
    );
    final style = theme
        .resolve(const AppPreferences())
        .chrome
        .surfaces['popup']!;
    expect(style.colors.length, 8);
    expect(style.opacity, .55);
    expect(style.blur, 8);
    expect(style.texture, .08);
    expect(style.shadow, .35);
    expect(style.duration, 180);
    expect(style.gloss, .3);
    final accessible = theme
        .resolve(const AppPreferences(highContrast: true, reducedMotion: true))
        .chrome
        .surfaces['popup']!;
    expect(accessible.colors, isEmpty);
    expect(accessible.opacity, 1);
    expect(accessible.blur, 0);
    expect(accessible.texture, 0);
    expect(accessible.gloss, 0);
    expect(accessible.duration, 0);
  });
  testWidgets('glass surfaces settle without an idle animation loop', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ThemeSurface(color: Colors.blue, child: Text('Static surface')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(
      const MaterialApp(
        home: StyledThemeSurface(
          style: ThemeSurfaceStyle(texture: .025, gloss: .22, duration: 120),
          color: Colors.blue,
          child: Text('Text remains accessible'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Text remains accessible'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
  Map<String, Object?> minimal() => {
    'schema': 1,
    'id': 'test',
    'name': 'Test',
    'extends': 'dark',
  };
  test('older/minimal themes inherit all semantic defaults', () {
    final theme = JsonTheme.parse(
      jsonEncode(minimal()),
    ).resolve(const AppPreferences());
    expect(
      theme.palette.background,
      DeltiecordPalette.forMode(DeltiecordThemeMode.dark).background,
    );
    expect(theme.chrome.blur, 0);
    expect(theme.chrome.opacity, 1);
  });
  test('references, unknown tokens and cyclic references fail safely', () {
    final theme = JsonTheme.parse(
      jsonEncode({
        ...minimal(),
        'tokens': {
          'accent.primary': '#123456',
          'accent.secondary': {'ref': 'accent.primary'},
          'surface.panel': {'ref': 'surface.rail'},
          'surface.rail': {'ref': 'surface.panel'},
          'future.token': 'ignored',
          'glass.blur': 99999,
        },
      }),
    ).resolve(const AppPreferences());
    expect(theme.secondary, const Color(0xff123456));
    expect(
      theme.palette.panel,
      DeltiecordPalette.forMode(DeltiecordThemeMode.dark).panel,
    );
    expect(theme.chrome.blur, 8);
  });
  test('malformed, oversized, deep and executable parents are rejected', () {
    for (final value in [
      '{}',
      '${'[' * 17}0${']' * 17}',
      ' ' * (JsonTheme.maxBytes + 1),
      jsonEncode({...minimal(), 'schema': 2}),
      jsonEncode({...minimal(), 'extends': 'https://example.org/theme.json'}),
      jsonEncode({
        ...minimal(),
        'settings': [
          {'id': 'script', 'label': 'Script', 'type': 'lua'},
        ],
      }),
    ]) {
      expect(() => JsonTheme.parse(value), throwsFormatException);
    }
    expect(
      JsonTheme.fromPreferences(const AppPreferences(themeJson: 'not json')),
      isNull,
    );
  });
  test(
    'Aero variants/settings are bounded; accessibility overrides effects',
    () async {
      final source = await rootBundle.loadString('assets/themes/aero.json');
      final theme = JsonTheme.parse(source);
      final prefs = AppPreferences(
        themeJson: source,
        themeSettings: const {'blur': 900, 'opacity': 0, 'variant': 'Light'},
      );
      final light = theme.resolve(prefs);
      expect(light.brightness, Brightness.light);
      expect(light.chrome.blur, 8);
      expect(light.chrome.opacity, .65);
      expect(theme.resolve(prefs.copyWith(highContrast: true)).chrome.blur, 0);
      expect(
        theme.resolve(prefs.copyWith(highContrast: true)).chrome.opacity,
        1,
      );
      expect(theme.resolve(prefs.copyWith(reducedMotion: true)).chrome.blur, 0);
    },
  );
  test(
    'custom document and parameters survive device-local appearance roundtrip',
    () async {
      final prefs = AppPreferences(
        themeJson: await rootBundle.loadString('assets/themes/aero.json'),
        themeSettings: const {'accent1': '#123456', 'variant': 'Light'},
      );
      final restored = DeviceAppearanceSnapshot.fromJson(
        DeviceAppearanceSnapshot.capture(prefs).json,
      ).applyTo(const AppPreferences());
      expect(restored.themeJson, prefs.themeJson);
      expect(restored.themeSettings, prefs.themeSettings);
      expect(restored.syncAppearance, isFalse);
    },
  );
  testWidgets(
    'dynamic controls apply live on narrow screens and reset safely',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = FakeBackend();
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: backend,
          builder: (context, _) => MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: JsonThemeSettings(backend: backend),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Try Aero Glass'));
        // Asset I/O completes on the real event loop, not the fake frame clock.
        for (var attempt = 0; attempt < 100; attempt++) {
          if (backend.preferences.themeJson.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Accent 1 — glass blue'), findsOneWidget);
      expect(find.text('Glass blur — 4.00'), findsOneWidget);
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(backend.preferences.themeSettings['variant'], 'Light');
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Use default appearance'));
      await tester.pumpAndSettle();
      expect(backend.preferences.themeJson, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      backend.dispose();
    },
  );
  testWidgets(
    'Aero updates the live app palette without replacing the session',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      final source = File('assets/themes/aero.json').readAsStringSync();
      await backend.updatePreferences(
        backend.preferences.copyWith(themeJson: source),
      );
      await tester.pumpAndSettle();
      final themed = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!;
      expect(themed.extension<ThemeChrome>()!.gloss, .22);
      expect(themed.colorScheme.primary, const Color(0xff8acfff));
      await backend.updatePreferences(
        backend.preferences.copyWith(themeSettings: const {'variant': 'Light'}),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
        Brightness.light,
      );
      expect(backend.status, SessionStatus.signedOut);
      await tester.pumpWidget(const SizedBox.shrink());
      backend.dispose();
    },
  );
}
