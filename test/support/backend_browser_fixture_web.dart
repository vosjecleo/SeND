import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The unit runner doesn't load SeND's HTML bootstrap. Supply only the presence
/// cleanup hook used by backend.dispose(), and restore the original global.
void Function() installBackendBrowserFixture() {
  final key = 'sendConfigurePresence'.toJS;
  final existed = globalContext.has('sendConfigurePresence');
  final old = globalContext.getProperty<JSAny?>(key);
  globalContext.setProperty(key, ((JSString? _) {}).toJS);
  return () {
    if (existed) {
      globalContext.setProperty(key, old);
    } else {
      globalContext.delete(key);
    }
  };
}
