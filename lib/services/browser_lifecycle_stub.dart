Future<bool> initializeBrowser() async => true;
Future<void> writeBrowserPushPreview(String? json) async {}
Future<String> subscribeBrowserPush() =>
    Future.error(UnsupportedError('Browser only'));
Future<void> clearBrowserNotifications(String roomId) async {}
Future<void> disableBrowserPush() async {}
Future<String> browserPushDiagnostics() async => 'Browser only';
Future<void> testBrowserPush() =>
    Future.error(UnsupportedError('Browser only'));
void setBrowserPushLease(String key) {}
Stream<Map<String, String>> get browserNotificationClicks =>
    const Stream.empty();
void configureBrowserPresence(String? json) {}
Future<void> publishBrowserPresence() async {}
bool get browserApplicationVisible => true;
Stream<bool> get browserVisibilityChanges => const Stream.empty();
bool? get browserKeyboardVisible => null;
Map<String, Object?>? get browserKeyboardGeometry => null;
Stream<Map<String, Object?>> get browserKeyboardGeometryChanges =>
    const Stream.empty();
