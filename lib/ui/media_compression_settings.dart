import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../backend/chat_backend.dart';
import '../models/media_compression.dart';

class MediaCompressionSettings extends StatelessWidget {
  const MediaCompressionSettings({required this.backend, super.key});
  final ChatBackend backend;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Upload quality', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      DropdownButtonFormField<ImageCompressionPreset>(
        key: ValueKey(backend.preferences.imageCompression),
        initialValue: backend.preferences.imageCompression,
        decoration: const InputDecoration(labelText: 'Default image quality'),
        items: const [
          DropdownMenuItem(
            value: ImageCompressionPreset.original,
            child: Text('Original'),
          ),
          DropdownMenuItem(
            value: ImageCompressionPreset.balanced,
            child: Text('Balanced, up to 2048 px'),
          ),
          DropdownMenuItem(
            value: ImageCompressionPreset.smaller,
            child: Text('Smaller, up to 1280 px'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            backend.updatePreferences(
              backend.preferences.copyWith(imageCompression: value),
            );
          }
        },
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey(
          '${backend.preferences.optimizeVideos}-${backend.preferences.videoCompression.name}',
        ),
        initialValue: backend.preferences.optimizeVideos
            ? backend.preferences.videoCompression.name
            : 'original',
        decoration: const InputDecoration(
          labelText: 'Default video compression',
        ),
        items: const [
          DropdownMenuItem(
            value: 'smaller',
            child: Text('Smaller files, up to 12 MiB'),
          ),
          DropdownMenuItem(
            value: 'balanced',
            child: Text('Balanced, up to 24 MiB'),
          ),
          DropdownMenuItem(value: 'original', child: Text('Original quality')),
        ],
        onChanged: (value) {
          if (value != null) {
            backend.updatePreferences(
              backend.preferences.copyWith(
                optimizeVideos: value != 'original',
                videoCompression: VideoCompressionPreset.parse(value),
              ),
            );
          }
        },
      ),
      const SizedBox(height: 8),
      Text(
        kIsWeb
            ? 'Browser videos keep their original quality. Image presets still apply.'
            : 'Compression runs on your device. Long clips may need trimming or an explicit choice to send the original. Captions, spoilers and encryption are preserved.',
      ),
    ],
  );
}
