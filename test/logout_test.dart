import 'package:deltiecord/app.dart';
import 'package:deltiecord/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fake_backend.dart';

void main() {
  testWidgets(
    'logout requires confirmation and cancellation preserves settings',
    (tester) async {
      final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
      await tester.pumpWidget(DeltiecordApp(backend: backend));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.status, SessionStatus.signedIn);
      expect(find.text('Settings'), findsWidgets);
    },
  );

  testWidgets('successful logout dismisses settings and returns to login', (
    tester,
  ) async {
    final backend = _LogoutBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(DeltiecordApp(backend: backend));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();
    expect(backend.status, SessionStatus.signedOut);
    expect(find.text('Settings'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('mobile logout stays above the system navigation buttons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 900);
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    final backend = FakeBackend()..currentStatus = SessionStatus.signedIn;
    await tester.pumpWidget(
      DeltiecordApp(backend: backend, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final logout = find.widgetWithText(ListTile, 'Log out');
    expect(tester.getBottomRight(logout).dy, lessThanOrEqualTo(900 - 48));
    await tester.tap(logout);
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _LogoutBackend extends FakeBackend {
  @override
  Future<void> logout() async {
    currentStatus = SessionStatus.signedOut;
    notifyListeners();
  }
}
