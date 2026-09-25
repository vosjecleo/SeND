import 'dart:typed_data';
import '../models/user_activity.dart';

class ActivityCandidate {
  const ActivityCandidate({
    required this.id,
    required this.name,
    this.kind,
    this.details = '',
    this.iconBytes,
    this.running = true,
    this.playback,
    this.lastFmUrl,
  });
  final String id, name, details;
  final ActivityKind? kind;
  final Uint8List? iconBytes;
  final bool running;
  final ActivityPlayback? playback;
  final Uri? lastFmUrl;
}
