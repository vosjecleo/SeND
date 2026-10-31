import 'dart:async';
import 'package:deltiecord/services/session_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reused client identity does not authorize old account work', () async {
    final scope = SessionScope();
    final old = scope.capture(), gate = Completer<void>();
    var published = false;
    final pending = () async {
      await gate.future;
      if (old.isCurrent) published = true;
    }();
    scope.invalidate();
    final next = scope.capture();
    gate.complete();
    await pending;
    expect(old.isCurrent, false);
    expect(next.isCurrent, true);
    expect(published, false);
    scope.dispose();
    expect(next.isCurrent, false);
    expect(scope.capture().isCurrent, false);
  });
}
