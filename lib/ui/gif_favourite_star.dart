import 'package:flutter/material.dart';
import '../services/gif_service.dart';

class GifFavouriteStar extends StatefulWidget {
  const GifFavouriteStar({
    required this.gif,
    required this.service,
    this.onChanged,
    super.key,
  });
  final GifSearchResult gif;
  final GifService service;
  final VoidCallback? onChanged;
  @override
  State<GifFavouriteStar> createState() => _GifFavouriteStarState();
}

class _GifFavouriteStarState extends State<GifFavouriteStar> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.service.favorites();
      if (mounted) setState(() {});
    } catch (_) {
      /* A tap can retry opening favourites. */
    }
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      await widget.service.toggleFavorite(widget.gif);
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not save this favourite.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.service.accountChanges,
      GifService.favouriteChanges,
    ]),
    builder: (context, _) {
      final selected = widget.service.isFavorite(widget.gif);
      return IconButton(
        tooltip: selected ? 'Remove favourite GIF' : 'Favourite GIF',
        onPressed: _busy ? null : _toggle,
        style: IconButton.styleFrom(backgroundColor: Colors.black54),
        icon: Icon(
          selected ? Icons.star : Icons.star_border,
          color: selected ? const Color(0xffffb300) : Colors.white,
        ),
      );
    },
  );
}
