import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/application_visibility.dart';

void main() {
  test('visible web pages remain foregrounded despite input/view blur', () {
    for (final state in [
      null,
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
    ]) {
      expect(
        applicationIsForeground(state, viewFocused: false, browser: true),
        isTrue,
      );
    }
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      expect(
        applicationIsForeground(state, viewFocused: true, browser: true),
        isFalse,
      );
    }
    expect(
      applicationIsForeground(
        AppLifecycleState.resumed,
        viewFocused: false,
        browser: false,
      ),
      isFalse,
    );
    expect(
      applicationIsForeground(
        AppLifecycleState.inactive,
        viewFocused: true,
        browser: false,
      ),
      isFalse,
    );
  });
}
