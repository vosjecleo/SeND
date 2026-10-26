import 'package:flutter/material.dart';
import '../services/emoji_repository.dart';
import 'emoji_typography.dart';

Future<void> showStockEmojiDetails(BuildContext context, String emoji) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emoji'),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji,
                style: colourEmojiStyle(
                  const TextStyle(fontSize: 112, height: 1.2),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<EmojiEntry>>(
                future: EmojiRepository.instance.load(),
                initialData: EmojiRepository.instance.cachedEntries,
                builder: (context, snapshot) {
                  final entry = snapshot.data
                      ?.where(
                        (e) =>
                            e.emoji.replaceAll('\ufe0f', '') ==
                            emoji.replaceAll('\ufe0f', ''),
                      )
                      .firstOrNull;
                  return SelectableText(
                    snapshot.hasData
                        ? ':${entry?.shortcode ?? 'emoji'}:'
                        : 'Loading name…',
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 8),
              const Text('Stock emoji'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
