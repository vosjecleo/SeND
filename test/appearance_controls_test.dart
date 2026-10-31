import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/accent_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'package:deltiecord/ui/theme_chooser.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';

void main() {
  testWidgets('colour picker has explicit Apply and closes without rollback', (
    tester,
  ) async {
    var color = 0xff123456;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccentColorPickerButton(
            color: color,
            onChanged: (value) => color = value,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('accent-hex-field')),
      '#ABCDEF',
    );
    expect(color, 0xffabcdef);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme and sizing continue to update after repeated resume', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    for (var i = 0; i < 4; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await backend.updatePreferences(
        backend.preferences.copyWith(
          themeMode: i.isEven
              ? DeltiecordThemeMode.light
              : DeltiecordThemeMode.dark,
          fontScale: i.isEven ? 1.2 : 1,
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme!.brightness,
        i.isEven ? Brightness.light : Brightness.dark,
      );
    }
    expect(tester.takeException(), isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('theme chooser is one row and fits a narrow scaled screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var value = DeltiecordThemeMode.regular;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
          child: Scaffold(
            body: ThemeChooser(value: value, onChanged: (v) => value = v),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('theme-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night'));
    await tester.pumpAndSettle();
    expect(value, DeltiecordThemeMode.night);
    expect(tester.takeException(), isNull);
  });

  testWidgets('theme and scale update repeatedly without a resume event', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    for (var i = 0; i < 5; i++) {
      await backend.updatePreferences(
        backend.preferences.copyWith(
          themeMode: i.isEven
              ? DeltiecordThemeMode.light
              : DeltiecordThemeMode.night,
          fontScale: i.isEven ? 1.3 : 1,
        ),
      );
      await tester.pumpAndSettle();
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(
        app.theme!.brightness,
        i.isEven ? Brightness.light : Brightness.dark,
      );
      final field = find.byType(TextField).first;
      expect(
        MediaQuery.textScalerOf(tester.element(field)).scale(10),
        i.isEven ? 13 : 10,
      );
    }
  });

  testWidgets('an older scale callback cannot restore an earlier theme', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    final oldSlider = tester.widget<Slider>(
      find.byKey(const Key('interface-scale-slider')),
    );
    await tester.tap(find.byKey(const Key('theme-chooser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(backend.preferences.themeMode, DeltiecordThemeMode.light);
    oldSlider.onChanged!(1.1);
    await tester.pump();
    expect(backend.preferences.themeMode, DeltiecordThemeMode.light);
    expect(backend.preferences.interfaceScale, 1.1);
  });

  testWidgets(
    'mobile appearance updates immediately without waiting for a theme ticker',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
      await tester.pumpWidget(
        DeltiecordApp(
          backend: backend,
          platformOverride: TargetPlatform.android,
        ),
      );
      for (final mode in [
        DeltiecordThemeMode.light,
        DeltiecordThemeMode.night,
        DeltiecordThemeMode.regular,
      ]) {
        await backend.updatePreferences(
          backend.preferences.copyWith(themeMode: mode, fontScale: 1.2),
        );
        await tester.pump();
        final field = find.byType(TextField).first;
        final context = tester.element(field);
        expect(
          Theme.of(context).brightness,
          mode == DeltiecordThemeMode.light
              ? Brightness.light
              : Brightness.dark,
        );
        expect(MediaQuery.textScalerOf(context).scale(10), 12);
      }
    },
  );

  testWidgets(
    'Windows icons use the generated accent palette and hover remains neutral',
    (tester) async {
      final backend = FakeBackend()
        ..currentPreferences = const AppPreferences().copyWith(
          accentColor: 0xff127e44,
          highContrast: true,
        );
      await tester.pumpWidget(
        DeltiecordApp(
          backend: backend,
          platformOverride: TargetPlatform.windows,
        ),
      );
      await tester.pump();
      final theme = tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
      final generated = ColorScheme.fromSeed(
        seedColor: const Color(0xff127e44),
        brightness: Brightness.dark,
        contrastLevel: 1,
      ).primary;
      expect(theme.colorScheme.primary, generated);
      expect(theme.iconTheme.color, generated);
      expect(
        theme.iconButtonTheme.style!.foregroundColor!.resolve({}),
        generated,
      );
      expect(
        theme.extension<DeltiecordPalette>()!.hover,
        DeltiecordPalette.forMode(backend.preferences.themeMode).hover,
      );
    },
  );

  testWidgets('backend events reuse app theme but preferences invalidate it', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    final original = tester.widget<MaterialApp>(find.byType(MaterialApp));
    for (var i = 0; i < 25; i++) {
      backend.notifyListeners();
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme,
        same(original.theme),
      );
    }
    await backend.updatePreferences(
      backend.preferences.copyWith(accentColor: 0xff123456),
    );
    await tester.pump();
    final changed = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      changed.theme!.colorScheme.primary,
      isNot(original.theme!.colorScheme.primary),
    );
    backend.currentStatus = SessionStatus.starting;
    backend.notifyListeners();
    await tester.pump();
    expect(find.text('Sign in'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    backend.dispose();
  });
}
