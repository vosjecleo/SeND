import 'package:flutter/material.dart';

import '../../backend/chat_backend.dart';
import '../../models/chat_models.dart';
import '../room_details_panel.dart';

class MobileDetailsPanel extends StatelessWidget {
  const MobileDetailsPanel({
    required this.backend,
    required this.room,
    required this.onDismiss,
    super.key,
  });
  final ChatBackend backend;
  final RoomSummary room;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('mobile-details-panel'),
    onHorizontalDragEnd: (details) {
      if ((details.primaryVelocity ?? 0) > 250) onDismiss();
    },
    child: RoomDetailsPanel(backend: backend, room: room, onDismiss: onDismiss),
  );
}
