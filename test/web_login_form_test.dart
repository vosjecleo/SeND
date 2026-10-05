@TestOn('browser')
library;

import 'package:deltiecord/ui/web_login_form_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  testWidgets('credential form excludes homeserver and reads silent autofill', (
    tester,
  ) async {
    (String, String, String)? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: WebLoginForm(
          registering: false,
          loading: false,
          onSubmit: (s, u, p) => submitted = (s, u, p),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(WebLoginForm)) as dynamic;
    web.document.body!.appendChild(state.debugDomRoot as web.HTMLElement);
    final mountingError = tester.takeException();
    if (mountingError != null) fail('Login form mount: $mountingError');
    expect(
      web.document.querySelector('#deltiecord-login'),
      isNotNull,
      reason: 'DOM credential form must be mounted',
    );
    final form =
        web.document.querySelector('#deltiecord-login')! as web.HTMLFormElement;
    final server =
        web.document.querySelector('#deltiecord-homeserver')!
            as web.HTMLInputElement;
    final username =
        form.querySelector('[autocomplete=username]')! as web.HTMLInputElement;
    final password =
        form.querySelector('[autocomplete=current-password]')!
            as web.HTMLInputElement;
    expect(form.contains(server), false);
    expect(server.type, 'url');
    expect(server.form, isNull);
    expect(form.querySelector('input[type=text]'), username);
    username.value = 'test-user';
    password.value = 'test-secret';
    // Password managers can fill without input/change events.
    form.dispatchEvent(web.Event('submit', web.EventInit(cancelable: true)));
    expect(submitted, (
      'https://matrix.deltie.net',
      'test-user',
      'test-secret',
    ));
    final eye =
        form.querySelector('button[aria-label="Show password"]')!
            as web.HTMLButtonElement;
    eye.click();
    expect(password.type, 'text');
    expect(password.value, 'test-secret');
    eye.click();
    expect(password.type, 'password');
    await tester.pumpWidget(const SizedBox());
    expect(password.value, '');
    expect(web.document.querySelector('#deltiecord-login'), isNull);
  });

  testWidgets('registration confirmation and invalid server cannot submit', (
    tester,
  ) async {
    var count = 0;
    Widget form(bool registering) => MaterialApp(
      home: WebLoginForm(
        registering: registering,
        loading: false,
        onSubmit: (_, _, _) => count++,
      ),
    );
    await tester.pumpWidget(form(false));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(WebLoginForm)) as dynamic;
    web.document.body!.appendChild(state.debugDomRoot as web.HTMLElement);
    final htmlForm =
        web.document.querySelector('#deltiecord-login')! as web.HTMLFormElement;
    final server =
        web.document.querySelector('#deltiecord-homeserver')!
            as web.HTMLInputElement;
    server.value = 'http://insecure.test';
    htmlForm.dispatchEvent(
      web.Event('submit', web.EventInit(cancelable: true)),
    );
    expect(count, 0);
    await tester.pumpWidget(form(true));
    await tester.pumpAndSettle();
    final refreshedState = tester.state(find.byType(WebLoginForm)) as dynamic;
    web.document.body!.appendChild(
      refreshedState.debugDomRoot as web.HTMLElement,
    );
    (htmlForm.querySelector('[name=username]')! as web.HTMLInputElement).value =
        'test';
    (htmlForm.querySelector('[name=password]')! as web.HTMLInputElement).value =
        'secret';
    final confirmation =
        htmlForm.querySelector('[name=password-confirmation]')!
            as web.HTMLInputElement;
    confirmation.value = 'different';
    htmlForm.dispatchEvent(
      web.Event('submit', web.EventInit(cancelable: true)),
    );
    expect(count, 0);
    confirmation.value = 'secret';
    htmlForm.dispatchEvent(
      web.Event('submit', web.EventInit(cancelable: true)),
    );
    expect(count, 1);
    expect(server.disabled, true);
  });
}
