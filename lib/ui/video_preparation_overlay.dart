import 'package:flutter/material.dart';
import '../services/video_preparation.dart';
import '../services/image_preparation.dart';
import '../backend/chat_backend.dart';

class VideoPreparationOverlay extends StatelessWidget {
  const VideoPreparationOverlay({required this.child, this.backend, super.key});
  final Widget child;
  final ChatBackend? backend;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      VideoPreparation.instance,
      ImagePreparation.instance,
      ?backend,
    ]),
    child: child,
    builder: (context, child) {
      final state = VideoPreparation.instance;
      final image = ImagePreparation.instance;
      final video = state.active;
      final upload = backend?.activeAttachmentUploads.firstOrNull;
      final preparing = video || image.active;
      return Stack(
        children: [
          child!,
          if (preparing || upload != null)
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
                                    !preparing
                                        ? 'Uploading ${upload!.attachment!.name}'
                                        : !video || state.failure == null
                                        ? 'Optimizing ${video ? state.name : image.name}'
                                        : 'Could not optimize ${state.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (preparing)
                                  TextButton(
                                    onPressed: video
                                        ? state.cancel
                                        : image.cancel,
                                    child: const Text('Cancel'),
                                  ),
                              ],
                            ),
                            if (video && state.failure != null) ...[
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
                            ] else ...[
                              LinearProgressIndicator(
                                value: !preparing
                                    ? upload?.preparationProgress
                                    : !video || state.progress == 0
                                    ? null
                                    : state.progress,
                              ),
                              if (preparing)
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
