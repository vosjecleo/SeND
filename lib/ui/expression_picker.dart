import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../backend/chat_backend.dart';
import '../services/gif_service.dart';
import '../services/favourite_reactions_store.dart';
import 'advanced_chat_dialogs.dart';
import 'deltiecord_theme.dart';
import 'emoji_picker_dialog.dart';
import 'giphy_dialog.dart';
import 'json_theme.dart';

/// One surface and one route for emoji, GIFs, and owned/shared sticker packs.
/// Returns EmojiEntry, GifSearchResult, or StickerSummary to the composer.
Future<Object?> showExpressionPicker(
  BuildContext context,
  ChatBackend backend,
  GifService giphy,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  if (!context.mounted) return null;
  final mobile = MediaQuery.sizeOf(context).width < 700;
  final content = _ExpressionPicker(backend: backend, giphy: giphy);
  if (mobile) {
    return showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      requestFocus: false,
      backgroundColor: Colors.transparent,
      builder: (context) => ThemeSurface(
        kind: 'popup',
        color: context.deltiecord.surface,
        child: SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .62,
            child: content,
          ),
        ),
      ),
    );
  }
  return showDialog<Object>(
    context: context,
    barrierColor:
        Theme.of(
              context,
            ).extension<ThemeChrome>()?.surfaces.containsKey('popup') ==
            true
        ? const Color(0x30000000)
        : null,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: ThemeSurface(
        kind: 'popup',
        color: context.deltiecord.surface,
        child: SizedBox(width: 600, height: 560, child: content),
      ),
    ),
  );
}

class _ExpressionPicker extends StatefulWidget {
  const _ExpressionPicker({required this.backend, required this.giphy});
  final ChatBackend backend;
  final GifService giphy;

  @override
  State<_ExpressionPicker> createState() => _ExpressionPickerState();
}

class _ExpressionPickerState extends State<_ExpressionPicker> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    FavouriteReactionsStore.instance.load();
    widget.backend.refreshStickerPacks();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            for (final (index, label, icon) in [
              (
                0,
                'Emoji',
                Theme.of(context).extension<ThemeChrome>()?.classicIcons == true
                    ? Icons.emoji_emotions
                    : Icons.emoji_emotions_outlined,
              ),
              (
                1,
                'GIFs',
                Theme.of(context).extension<ThemeChrome>()?.classicIcons == true
                    ? Icons.gif_box
                    : Icons.gif_box_outlined,
              ),
              (
                2,
                'Stickers',
                Theme.of(context).extension<ThemeChrome>()?.classicIcons == true
                    ? Icons.sticky_note_2
                    : Icons.sticky_note_2_outlined,
              ),
            ])
              Expanded(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: _tab == index
                        ? context.deltiecord.island
                        : Colors.transparent,
                  ),
                  onPressed: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    SystemChannels.textInput.invokeMethod<void>(
                      'TextInput.hide',
                    );
                    setState(() => _tab = index);
                  },
                  icon: ThemeIcon(icon, size: 20),
                  label: Text(label),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: switch (_tab) {
            0 => EmojiPickerDialog(backend: widget.backend, embedded: true),
            1 => GiphyDialog(
              service: widget.giphy,
              embedded: true,
              autoplay:
                  widget.backend.preferences.autoplayGifs &&
                  !widget.backend.preferences.reducedMotion,
            ),
            _ => StickerPickerContents(backend: widget.backend),
          },
        ),
      ),
    ],
  );
}
