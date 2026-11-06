import 'dart:async';
import 'dart:typed_data';
import 'dart:math' show Random;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../services/gif_service.dart';
import '../services/encoded_image_dimensions.dart';
import 'lifecycle_memory_image.dart';
import 'gif_favourite_star.dart';
import '../services/gif_categories.dart';

class _CategoryGif extends StatefulWidget {
  const _CategoryGif({
    required this.service,
    required this.query,
    required this.autoplay,
  });
  final GifService service;
  final String query;
  final bool autoplay;
  @override
  State<_CategoryGif> createState() => _CategoryGifState();
}

class _CategoryGifState extends State<_CategoryGif> {
  late final Future<Uint8List?> _bytes = _load();
  Future<Uint8List?> _load() => widget.service.categoryRequest(() async {
    try {
      if (!mounted) return null;
      final items = widget.query == 'Favourites'
          ? await widget.service.favorites()
          : widget.query == 'Frequently used'
          ? widget.service.frequent
          : await widget.service.categoryLinks(widget.query);
      final top = items.take(5).toList();
      if (top.isEmpty || !mounted) return null;
      return await widget.service.preview(top[Random().nextInt(top.length)]);
    } catch (_) {
      return null;
    }
  });

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) => snapshot.data == null
          ? const SizedBox.expand()
          : LifecycleMemoryImage(
              bytes: snapshot.data!,
              animated: true,
              autoplay: widget.autoplay,
              fit: BoxFit.cover,
              decodeWidth: 360,
            ),
    ),
  );
}

class _GifPreview extends StatefulWidget {
  const _GifPreview({
    required this.service,
    required this.gif,
    required this.autoplay,
    required this.onSelect,
    required this.onHold,
    super.key,
  });
  final GifService service;
  final GifSearchResult gif;
  final bool autoplay;
  final VoidCallback onSelect, onHold;
  @override
  State<_GifPreview> createState() => _GifPreviewState();
}

class _GifPreviewState extends State<_GifPreview> with WidgetsBindingObserver {
  late Future<(Uint8List, double)> _future = _load();
  bool _failed = false;
  Future<(Uint8List, double)> _load() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final bytes = await widget.service.preview(widget.gif);
        final size = widget.gif.width == null || widget.gif.height == null
            ? await readEncodedImageDimensions(bytes)
            : null;
        return (
          bytes,
          size == null
              ? widget.gif.aspectRatio
              : (size.width / size.height).clamp(.1, 10).toDouble(),
        );
      } catch (_) {
        if (attempt == 1) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) rethrow;
      }
    }
    throw StateError('GIF unavailable');
  }

  void _retry() => setState(() {
    _failed = false;
    _future = _load();
  });
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _failed) _retry();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(Uint8List, double)>(
    future: _future,
    builder: (context, snapshot) {
      _failed = snapshot.hasError;
      return AspectRatio(
        aspectRatio: snapshot.hasError
            ? 1.5
            : snapshot.data?.$2 ?? widget.gif.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: InkWell(
              onTap: snapshot.hasData
                  ? widget.onSelect
                  : snapshot.hasError
                  ? _retry
                  : null,
              onLongPress: widget.onHold,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  snapshot.hasData
                      ? LifecycleMemoryImage(
                          bytes: snapshot.data!.$1,
                          animated: true,
                          autoplay: widget.autoplay,
                          fit: BoxFit.contain,
                          decodeWidth: 640,
                        )
                      : snapshot.hasError
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Retry GIF',
                                onPressed: _retry,
                                icon: const Icon(Icons.refresh),
                              ),
                              if (widget.gif.message != null)
                                const Text(
                                  'Original GIF unavailable',
                                  textAlign: TextAlign.center,
                                ),
                            ],
                          ),
                        )
                      : const SizedBox.expand(),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GifFavouriteStar(
                      gif: widget.gif,
                      service: widget.service,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _GifSection { home, favourites, frequent, trending, search }

class GiphyDialog extends StatefulWidget {
  const GiphyDialog({
    required this.service,
    this.embedded = false,
    this.autoplay = true,
    super.key,
  });
  final GifService service;
  final bool embedded, autoplay;
  @override
  State<GiphyDialog> createState() => _GiphyDialogState();
}

class _GiphyDialogState extends State<GiphyDialog> with WidgetsBindingObserver {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  int _generation = 0, _page = 0;
  bool _loading = false, _hasMore = false;
  String? _error;
  _GifSection _section = _GifSection.home;
  List<GifSearchResult> _results = [];
  Listenable? _account;
  String get _title => switch (_section) {
    _GifSection.home => 'GIFs',
    _GifSection.favourites => 'Favourites',
    _GifSection.frequent => 'Frequently used',
    _GifSection.trending => 'Trending GIFs',
    _GifSection.search => 'Search results',
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _query.addListener(_schedule);
    _scroll.addListener(_nearEnd);
    _account = widget.service.accountChanges;
    _account?.addListener(_accountChanged);
    unawaited(widget.service.warmCategories());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _account?.removeListener(_accountChanged);
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _accountChanged() {
    if (_section == _GifSection.favourites ||
        _section == _GifSection.frequent) {
      unawaited(_loadLocal());
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _error != null) {
      unawaited(_loadNext());
    }
  }

  void _schedule() {
    _debounce?.cancel();
    _generation++;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _open(
        _query.text.trim().isEmpty ? _GifSection.home : _GifSection.search,
      ),
    );
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 400 &&
        !_loading &&
        _hasMore &&
        _error == null) {
      unawaited(_loadNext());
    }
  }

  Future<void> _open(_GifSection section) async {
    _generation++;
    setState(() {
      _section = section;
      _results = [];
      _page = 0;
      _hasMore = false;
      _error = null;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (section == _GifSection.home) return;
    if (section == _GifSection.favourites || section == _GifSection.frequent) {
      await _loadLocal();
    } else {
      _hasMore = true;
      await _loadNext();
    }
  }

  Future<void> _loadLocal() async {
    final generation = _generation;
    try {
      final values = _section == _GifSection.favourites
          ? await widget.service.favorites()
          : widget.service.frequent;
      if (mounted && generation == _generation) {
        setState(() {
          _results = values;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load saved GIFs.');
      }
    }
  }

  Future<void> _loadNext() async {
    if (_loading || _section == _GifSection.home) return;
    if (_section == _GifSection.favourites ||
        _section == _GifSection.frequent) {
      return _loadLocal();
    }
    final generation = _generation, next = _page + 1;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.page(
        query: _section == _GifSection.trending ? '' : _query.text.trim(),
        page: next,
      );
      if (!mounted || generation != _generation) return;
      final seen = _results.map((g) => g.shareUrl).toSet();
      final fresh = page.items.where((g) => seen.add(g.shareUrl)).toList();
      setState(() {
        _results = [..._results, ...fresh];
        _page = next;
        _hasMore = page.hasMore && fresh.isNotEmpty;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load GIFs. Try again.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nearEnd();
        });
      }
    }
  }

  Future<void> _hold(GifSearchResult gif) async {
    try {
      await widget.service.toggleFavorite(gif);
      if (!mounted) return;
      if (_section == _GifSection.favourites) await _loadLocal();
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              widget.service.isFavorite(gif)
                  ? 'GIF added to favourites.'
                  : 'GIF removed from favourites.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Could not save this favourite.')),
        );
      }
    }
  }

  Widget _home() => GridView.count(
    key: const ValueKey('gif-home'),
    crossAxisCount: 2,
    childAspectRatio: 1.8,
    mainAxisSpacing: 8,
    crossAxisSpacing: 8,
    children: [
      _category(
        'Favourites',
        Icons.favorite,
        () => _open(_GifSection.favourites),
      ),
      _category(
        'Frequently used',
        Icons.history,
        () => _open(_GifSection.frequent),
      ),
      _category('Trending', null, () => _open(_GifSection.trending)),
      for (final term in gifCategorySearches.skip(1))
        _category(term, null, () {
          _debounce?.cancel();
          _query.removeListener(_schedule);
          _query.text = term;
          _query.addListener(_schedule);
          unawaited(_open(_GifSection.search));
        }),
    ],
  );
  Widget _category(String label, IconData? icon, VoidCallback onTap) =>
      Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _CategoryGif(
                service: widget.service,
                query: label == 'Trending' ? '' : label,
                autoplay: widget.autoplay,
              ),
              const ColoredBox(color: Colors.black38),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[Icon(icon), const SizedBox(height: 6)],
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: 620,
      height: 500,
      child: Column(
        children: [
          TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              _debounce?.cancel();
              unawaited(
                _open(
                  _query.text.trim().isEmpty
                      ? _GifSection.trending
                      : _GifSection.search,
                ),
              );
            },
            decoration: InputDecoration(
              hintText: 'Search KLIPY',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Search GIFs',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  _debounce?.cancel();
                  unawaited(
                    _open(
                      _query.text.trim().isEmpty
                          ? _GifSection.trending
                          : _GifSection.search,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (_section != _GifSection.home)
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to GIF categories',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    _query.removeListener(_schedule);
                    _query.clear();
                    _query.addListener(_schedule);
                    unawaited(_open(_GifSection.home));
                  },
                ),
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          Expanded(
            child: _section == _GifSection.home
                ? _home()
                : CustomScrollView(
                    key: ValueKey('gif-results-${_section.name}'),
                    controller: _scroll,
                    scrollCacheExtent: const ScrollCacheExtent.pixels(150),
                    slivers: [
                      SliverMasonryGrid.count(
                        crossAxisCount: 2,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childCount: _results.length,
                        itemBuilder: (context, index) {
                          final gif = _results[index];
                          return _GifPreview(
                            key: ValueKey(gif.shareUrl),
                            service: widget.service,
                            gif: gif,
                            autoplay: widget.autoplay,
                            onSelect: () => Navigator.of(context).pop(gif),
                            onHold: () => unawaited(_hold(gif)),
                          );
                        },
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: _loading
                              ? const Center(
                                  child: SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : _error != null
                              ? Column(
                                  children: [
                                    Text(_error!),
                                    TextButton(
                                      onPressed: _loadNext,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                )
                              : _results.isEmpty
                              ? const Center(child: Text('No GIFs found.'))
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
    return widget.embedded
        ? content
        : AlertDialog(title: const Text('GIFs'), content: content);
  }
}
