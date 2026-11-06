import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/ui/channel_join_indicator.dart';
import 'package:deltiecord/ui/create_server_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';
import 'support/widget_helpers.dart';

class _Backend extends FakeBackend {
  int microphones = 0, devices = 0, storage = 0;
  String? createdAccess;
  @override
  Future<void> refreshAudioInputs() async {
    microphones++;
  }

  @override
  Future<void> refreshDevices() async {
    devices++;
  }

  @override
  Future<void> refreshStorageUsage() async {
    storage++;
  }

  @override
  Future<void> createSpace({
    required String name,
    String topic = '',
    bool encrypted = true,
    String channelAccess = 'invite',
  }) async {
    createdAccess = channelAccess;
  }
}

void main() {
  testWidgets(
    'settings prioritize everyday pages and refresh other data lazily',
    (tester) async {
      final backend = _Backend()..currentStatus = SessionStatus.signedIn;
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final navigation = find.byKey(const ValueKey('settings-navigation-list'));
      Finder entry(String label) =>
          find.descendant(of: navigation, matching: find.text(label));
      expect(
        tester.getTopLeft(entry('Notifications')).dy,
        lessThan(tester.getTopLeft(entry('Appearance')).dy),
      );
      expect(
        tester.getTopLeft(entry('Appearance')).dy,
        lessThan(tester.getTopLeft(entry('Chats & media')).dy),
      );
      expect(backend.microphones, 0);
      expect(backend.devices, 0);
      expect(backend.storage, 0);
      await tester.enterText(
        find.byKey(const ValueKey('settings-search')),
        'microphone',
      );
      await tester.pumpAndSettle();
      expect(entry('Audio & video'), findsOneWidget);
      expect(entry('About'), findsNothing);
      await tester.tap(entry('Audio & video'));
      await tester.pumpAndSettle();
      expect(backend.microphones, 1);
      expect(backend.devices, 0);
      expect(backend.storage, 0);
    },
  );
  testWidgets('Chats & media owns compression and the send-key preference', (
    tester,
  ) async {
    final backend = _Backend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await openSettingsSection(tester, 'Chats & media');
    expect(find.text('Default image quality'), findsOneWidget);
    expect(find.text('Default video compression'), findsOneWidget);
    await tester.tap(find.text('Send with Ctrl+Enter'));
    await tester.pumpAndSettle();
    expect(backend.preferences.sendWithCtrlEnter, true);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  for (final height in [30.0, 32.0]) {
    testWidgets(
      'unjoined marker does not resize rows or block opening, minimum=$height',
      (tester) async {
        var opened = 0;
        Widget row(bool joined, String key) => ChannelJoinIndicator(
          key: ValueKey(key),
          joined: joined,
          child: ListTile(
            dense: true,
            minTileHeight: height,
            visualDensity: const VisualDensity(vertical: -4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.tag, size: 20),
            title: const Text(
              'Channel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => opened++,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: Column(
                  children: [row(true, 'joined'), row(false, 'unjoined')],
                ),
              ),
            ),
          ),
        );
        final joined = tester.getRect(find.byKey(const ValueKey('joined'))),
            unjoined = tester.getRect(find.byKey(const ValueKey('unjoined')));
        expect(joined.size, unjoined.size);
        final titles = find.text('Channel');
        expect(
          tester.getTopLeft(titles.first).dx,
          tester.getTopLeft(titles.last).dx,
        );
        final icon = find.byKey(const ValueKey('unjoined-channel-indicator'));
        expect(tester.getRect(icon).right, closeTo(unjoined.right - 4, .1));
        expect(tester.getRect(icon).center.dy, closeTo(unjoined.center.dy, .1));
        await tester.tapAt(tester.getCenter(icon));
        await tester.pumpAndSettle();
        expect(opened, 1);
      },
    );
  }
  testWidgets(
    'server creation keeps invite-only default and exposes channel access',
    (tester) async {
      final backend = _Backend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCreateServerDialog(context, backend),
                child: const Text('Create server'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Create server'));
      await tester.pumpAndSettle();
      final access = find.byType(DropdownButtonFormField<String>);
      expect(
        tester.widget<DropdownButtonFormField<String>>(access).initialValue,
        'invite',
      );
      await tester.enterText(find.byType(TextField).first, 'New server');
      await tester.tap(access);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Members of this server').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();
      expect(backend.createdAccess, 'restricted');
    },
  );
}
