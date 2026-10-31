import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/models/user_activity.dart';
import 'package:deltiecord/services/activity_candidate.dart';
import 'package:deltiecord/services/activity_source.dart';

class Games extends DesktopActivitySource {
  bool playing = false;
  @override
  bool get supported => true;
  @override
  Future<List<ActivityCandidate>> scan(ActivitySettings settings) async =>
      playing && settings.detect
      ? [
          const ActivityCandidate(
            id: 'game',
            name: 'Game',
            kind: ActivityKind.game,
          ),
        ]
      : [];
  @override
  Future<void> dispose() async {}
}
