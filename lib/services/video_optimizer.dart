export 'video_optimizer_stub.dart'
    if (dart.library.js_interop) 'video_optimizer_web.dart'
    if (dart.library.io) 'video_optimizer_native.dart';
