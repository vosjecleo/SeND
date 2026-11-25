import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The unit runner doesn't load SeND's HTML bootstrap. Supply only the presence
/// presence hooks, and restore the original globals.
void Function() installBackendBrowserFixture({
  bool publicationSucceeded = false,
}) {
  const publishKey = 'sendPublishPresence';
  final hadPublish = globalContext.has(publishKey);
  final oldPublish = globalContext.getProperty<JSAny?>(publishKey.toJS);
  globalContext.setProperty(
    publishKey.toJS,
    (() => Future<JSBoolean>.value(publicationSucceeded.toJS).toJS).toJS,
  );
  final key = 'sendConfigurePresence'.toJS;
  final existed = globalContext.has('sendConfigurePresence');
  final old = globalContext.getProperty<JSAny?>(key);
  globalContext.setProperty(key, ((JSString? _) {}).toJS);
  return () {
    if (hadPublish) {
      globalContext.setProperty(publishKey.toJS, oldPublish);
    } else {
      globalContext.delete(publishKey.toJS);
    }
    if (existed) {
      globalContext.setProperty(key, old);
    } else {
      globalContext.delete(key);
    }
  };
}
