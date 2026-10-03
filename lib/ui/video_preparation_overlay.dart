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
                                    state.failure == null
                                        ? 'Optimizing ${state.name}'
                                        : 'Could not optimize ${state.name}',
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
                            if (state.failure != null) ...[
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 120,
                                ),
                                child: SingleChildScrollView(
                                  child: Text(state.failure!),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        state.recover(VideoRecovery.retry),
                                    child: const Text('Retry compression'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        state.recover(VideoRecovery.original),
                                    child: const Text('Send original'),
                                  ),
                                ],
                              ),
                              const Text(
                                'Original quality may use more data. Nothing has been uploaded yet.',
                              ),
                            ] else ...[
                              LinearProgressIndicator(
                                value: state.progress == 0
                                    ? null
                                    : state.progress,
                              ),
                              const Text(
                                'Local preparation · not uploaded yet',
                              ),
                            ],
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
