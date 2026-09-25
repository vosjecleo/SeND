import '../models/user_activity.dart';
import 'activity_candidate.dart';

class DesktopActivitySource {
  bool get supported => false;
  String? get warning => null;
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async => [];
  Future<void> dispose() async {}
}
