Future<bool> initializeBrowser() async => true;
Future<String> subscribeBrowserPush() =>
    Future.error(UnsupportedError('Browser only'));
Future<void> clearBrowserNotifications(String roomId) async {}
Future<void> disableBrowserPush() async {}
void setBrowserPushLease(String key) {}
Stream<Map<String, String>> get browserNotificationClicks =>
    const Stream.empty();
