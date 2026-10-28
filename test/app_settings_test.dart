import 'package:deltiecord/ui/plain_message_editor.dart';

import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/deltiecord_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_backend.dart';

void main() {
  testWidgets('shows login controls when signed out', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('SeND'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('new installs defer emoji shaping to the platform font stack', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedOut;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.textTheme.bodyMedium!.fontFamilyFallback, isNull);
  });

  for (final mode in DeltiecordThemeMode.values) {
    testWidgets('modal surfaces use the $mode SeND theme palette', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..currentStatus = SessionStatus.signedOut
        ..currentPreferences = AppPreferences(themeMode: mode);
      await tester.pumpWidget(DeltiecordApp(backend: backend));

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final palette = DeltiecordPalette.forMode(mode);
      expect(app.theme!.bottomSheetTheme.modalBackgroundColor, palette.surface);
      expect(app.theme!.dialogTheme.backgroundColor, palette.surface);
      expect(app.theme!.colorScheme.surfaceContainer, palette.surface);
    });
  }

  testWidgets('opens the v0.4 settings workspace', (tester) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Accessibility'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('About'),
      100,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('settings-navigation-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('About', skipOffstage: false), findsOneWidget);
    expect(find.text('Advanced', skipOffstage: false), findsNothing);
    expect(find.text('@deltie:example.org'), findsWidgets);
  });

  testWidgets('appearance exposes themes, scaling, and exact colour', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('theme-chooser')));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Night'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('interface-scale-slider')), findsOneWidget);
    expect(find.byKey(const Key('compactness-slider')), findsNothing);
    final colourWheelButton = find.textContaining('Open colour wheel');
    await tester.ensureVisible(colourWheelButton);
    await tester.pumpAndSettle();
    await tester.tap(colourWheelButton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accent-colour-wheel')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('accent-hex-field')),
      '#123456',
    );
    await tester.pump();
    expect(backend.preferences.accentColor, 0xff123456);
  });

  testWidgets('direct link previews require an explicit privacy opt-in', (
    tester,
  ) async {
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Privacy'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Privacy'));
    await tester.pumpAndSettle();

    expect(backend.preferences.fetchDirectLinkPreviews, isFalse);
    expect(find.textContaining('see your IP address'), findsOneWidget);
    await tester.tap(find.byKey(const Key('direct-link-preview-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Known providers only').last);
    await tester.pumpAndSettle();
    expect(backend.preferences.fetchDirectLinkPreviews, isTrue);
    expect(
      backend.preferences.directLinkPreviewMode,
      DirectLinkPreviewMode.trustedProviders,
    );
  });

  testWidgets('shows an explicit offline state', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentConnectionStatus = ConnectionStatus.offline;
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('opens settings with the control-comma shortcut', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..roomList = const [
        RoomSummary(
          id: '!shortcut:example.org',
          name: 'shortcut-room',
          lastMessage: '',
          unreadCount: 0,
          usesChannelIcon: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.text('shortcut-room'));
    await tester.pump();
    await tester.tap(find.byType(PlainMessageEditor));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Homeserver'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('shows SDK-independent Matrix device sessions', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..deviceList = const [
        DeviceSessionSummary(
          id: 'TESTDEVICE',
          displayName: 'SeND Desktop',
          current: true,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices'));
    await tester.pump();

    expect(find.text('SeND Desktop (this device)'), findsOneWidget);
    expect(find.textContaining('TESTDEVICE'), findsOneWidget);
  });

  testWidgets('removes another device only after password confirmation', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..deviceList = const [
        DeviceSessionSummary(
          id: 'OLDDEVICE',
          displayName: 'Old laptop',
          current: false,
        ),
      ];
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices'));
    await tester.pump();
    await tester.tap(find.byTooltip('Remove device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(backend.removedDeviceId, 'OLDDEVICE');
    expect(backend.removalPassword, 'secret');
  });

  testWidgets('prompts an unverified device for recovery', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsRecovery,
        keyBackupEnabled: true,
        crossSigningEnabled: true,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));

    expect(find.text('Fix encryption'), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open encryption & recovery'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, 'Recovery required'),
      findsOneWidget,
    );
    expect(find.text('Recover & verify'), findsOneWidget);
    expect(find.text('Encrypted key backup'), findsWidgets);
  });

  testWidgets('requires saving a newly generated recovery key', (tester) async {
    final backend = FakeBackend()
      ..currentStatus = SessionStatus.signedIn
      ..security = const EncryptionSetupState(
        status: EncryptionSetupStatus.needsSetup,
      );
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Security'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open encryption & recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up encryption'));
    await tester.pumpAndSettle();

    expect(find.text('recovery-key'), findsOneWidget);
    expect(find.text('I\'ve saved my recovery key.'), findsOneWidget);
    final done = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Done'),
    );
    expect(done.onPressed, isNull);
  });
}
