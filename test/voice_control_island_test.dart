import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:deltiecord/models/rtc_connectivity.dart';
import 'package:deltiecord/ui/voice_control_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show FakeBackend;

class _VoiceBackend extends FakeBackend {
  bool left = false;
  RtcConnectivity health = const RtcConnectivity();
  @override
  RtcConnectivity get rtcConnectivity => health;
  @override
  Future<void> leaveVoiceRoom() async {
    left = true;
  }
}

void main() {
  testWidgets('floating controls remain available outside the call room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = _VoiceBackend()
      ..currentStatus = SessionStatus.signedIn
      ..currentActiveVoiceId = 'another-room'
      ..currentVoiceStatus = VoiceConnectionStatus.connected;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.pumpAndSettle();
    final island = find.byType(VoiceControlIsland);
    expect(island, findsOneWidget);
    await tester.tap(
      find.descendant(of: island, matching: find.byTooltip('Mute')),
    );
    await tester.pump();
    expect(backend.muted, isTrue);
    await tester.tap(
      find.descendant(of: island, matching: find.byTooltip('Deafen')),
    );
    await tester.pump();
    expect(backend.deafened, isTrue);
    await tester.tap(
      find.descendant(of: island, matching: find.byTooltip('Disconnect')),
    );
    expect(backend.left, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'diagnostics distinguish RTC from room membership and update ping',
    (tester) async {
      final backend = _VoiceBackend();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: backend,
              builder: (context, _) => RtcConnectivityIcon(backend: backend),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.help), findsNothing);
      backend.currentVoiceStatus = VoiceConnectionStatus.connected;
      backend.notifyListeners();
      await tester.pump();
      expect(find.byIcon(Icons.help), findsOneWidget);
      await tester.tap(find.byIcon(Icons.help));
      await tester.pumpAndSettle();
      expect(find.textContaining('RTC ping unavailable'), findsOneWidget);
      backend.health = const RtcConnectivity(
        state: RtcConnectivityState.connected,
        pingMilliseconds: 42,
        detail: 'RTC connected',
      );
      backend.notifyListeners();
      await tester.pump();
      expect(find.textContaining('42 ms'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
