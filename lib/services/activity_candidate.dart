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
    this.lastFmArtwork,
    this.steamAppId,
    this.priority = 0,
  });
  final String id, name, details;
  final ActivityKind? kind;
  final Uint8List? iconBytes;
  final bool running;
  final ActivityPlayback? playback;
  final Uri? lastFmUrl;
  final Uri? lastFmArtwork;
  final String? steamAppId;
  final int priority;
}
