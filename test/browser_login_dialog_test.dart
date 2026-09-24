import 'package:deltiecord/models/login_methods.dart';
import 'package:deltiecord/ui/browser_login_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show FakeBackend;

class _DiscoveryBackend extends FakeBackend {
  bool offerOidc = false;
  @override
  Future<LoginMethods> discoverLoginMethods(Uri homeserver) async =>
      LoginMethods(
        homeserver: homeserver,
        password: !offerOidc,
        oidc: offerOidc,
      );
}

void main() {
  testWidgets('only offers browser methods actually discovered', (
    tester,
  ) async {
    final backend = _DiscoveryBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: BrowserLoginDialog(
          backend: backend,
          homeserver: 'https://matrix.example.org',
        ),
      ),
    );
    await tester.tap(find.text('Check server'));
    await tester.pumpAndSettle();
    expect(find.textContaining('password sign-in only'), findsOneWidget);
    expect(find.text('Continue with OIDC'), findsNothing);
    expect(find.text('Continue with SSO'), findsNothing);
    backend.offerOidc = true;
    await tester.tap(find.text('Check server'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with OIDC'), findsOneWidget);
    expect(find.text('Continue with SSO'), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      'https://another.example.org',
    );
    await tester.pump();
    expect(find.text('Continue with OIDC'), findsNothing);
  });
}
