export '../models/socks_proxy_config.dart';
export 'socks_proxy_native.dart'
    if (dart.library.js_interop) 'socks_proxy_web.dart';
