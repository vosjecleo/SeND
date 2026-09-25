import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Browser input/view focus is not page visibility. In particular, WebKit can
/// blur the Flutter view while native inputs or browser chrome have focus.
/// Hidden/paused pages remain backgrounded; native focus behaviour is unchanged.
bool applicationIsForeground(
  AppLifecycleState? state, {
  required bool viewFocused,
  bool browser = kIsWeb,
}) => browser
    ? state == null ||
          state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive
    : viewFocused && (state == null || state == AppLifecycleState.resumed);
