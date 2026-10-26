import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/unified_push.dart';
import 'package:deltiecord/ui/notification_diagnostics.dart';

void main() {
  test('diagnostics never copy endpoints, tokens or arbitrary errors', () {
    final report = notificationStateReport(
      const UnifiedPushState(
        distributor: 'org.unifiedpush.distributor.sunup',
        endpoint: 'https://push.test/private-token',
        error: 'https://push.test/private-token',
        lastWorkerResult: 'https://push.test/private-token',
        lastTestResult: 'receiver_verified',
      ),
    );
    expect(report, contains('sunup'));
    expect(report, contains('Endpoint saved: true'));
    expect(report, contains('receiver_verified'));
    expect(report, contains('Registration error: true'));
    expect(report, isNot(contains('private-token')));
    expect(report, isNot(contains('https://')));
  });
}
