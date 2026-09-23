import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_io/universal_io.dart' as io;

export 'package:universal_io/universal_io.dart' hide Platform;

/// OS integration gates must not mistake an Android/iOS browser for a native
/// app. Presentation uses Flutter's target platform; files/channels use these
/// capabilities. Browser HTTP remains subject to CORS, not native DNS access.
abstract final class Platform {
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
  static String get operatingSystem =>
      kIsWeb ? 'web' : io.Platform.operatingSystem;
}
