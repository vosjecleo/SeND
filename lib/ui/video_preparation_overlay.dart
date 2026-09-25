import 'package:flutter/material.dart';
import '../services/video_preparation.dart';

class VideoPreparationOverlay extends StatelessWidget {
  const VideoPreparationOverlay({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: VideoPreparation.instance,
    child: child,
    builder: (context, child) {
      final state = VideoPreparation.instance;
      return Stack(
        children: [
          child!,
          if (state.active)
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Optimizing ${state.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TextButton(
                                  onPressed: state.cancel,
                                  child: const Text('Cancel'),
                                ),
                              ],
                            ),
                            LinearProgressIndicator(
                              value: state.progress == 0
                                  ? null
                                  : state.progress,
                            ),
                            const Text('Local preparation · not uploaded yet'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
