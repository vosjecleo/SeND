import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import 'deltiecord_theme.dart';
import 'lifecycle_memory_image.dart';
import 'mobile/mobile_media.dart';
import 'history_index_settings.dart';
import '../services/message_search.dart';

enum RoomSearchSection { messages, media, files, links }

Future<void> showRoomSearchDialog(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
  RoomSearchSection initialSection = RoomSearchSection.messages,
}) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    child: SizedBox(
      width: 760,
      height: 680,
      child: RoomSearchPanel(
        backend: backend,
        onOpen: onOpen,
        initialSection: initialSection,
      ),
    ),
  ),
);

Future<void> showRoomSearchSheet(
  BuildContext context,
  ChatBackend backend, {
  required Future<void> Function(String eventId) onOpen,
  RoomSearchSection initialSection = RoomSearchSection.messages,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: RoomSearchPanel(
      backend: backend,
      onOpen: onOpen,
      initialSection: initialSection,
    ),
  ),
);

/// Opening search loads one page. A query continues through empty pages until
/// it finds results or the user stops it; scrolling loads subsequent matches.
class RoomSearchPanel extends StatefulWidget {
  const RoomSearchPanel({
    required this.backend,
    required this.onOpen,
    this.initialSection = RoomSearchSection.messages,
    super.key,
  });

  final ChatBackend backend;
  final Future<void> Function(String eventId) onOpen;
  final RoomSearchSection initialSection;

  @override
  State<RoomSearchPanel> createState() => _RoomSearchPanelState();
}

class _RoomSearchPanelState extends State<RoomSearchPanel>
    with SingleTickerProviderStateMixin {
  final _resultsScroll = ScrollController();
  int _queryGeneration = 0;

  final _query = TextEditingController();
  final _fromKey = GlobalKey();
  late final TabController _tabs;
  Timer? _debounce;
  List<ChatMessage> _serverResults = const [];
  bool _searching = false;
  bool _loadingOlder = false;
  int _paginationPasses = 0;
  bool _searchStopped = false;
  int _page = 0, _lastTab = 0;
  bool _navigating = false;
  bool _reloadTabAfterRequest = false;
  static const _pageSize = 10;
  final _catalogResults = <int, List<ChatMessage>>{};
  String? get _kind => switch (_tabs.index) {
    1 => 'media',
    2 => 'document',
    3 => 'link',
    _ => null,
  };
  bool get _canLoadOlder => _query.text.trim().isEmpty
      ? _kind != null
            ? widget.backend.canLoadMoreCatalog(
                widget.backend.selectedRoom?.id ?? '',
                _kind!,
              )
            : widget.backend.canLoadMoreHistory
      : widget.backend.canLoadMoreSearchResults;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showHistoryIndexPrompt(context, widget.backend);
    });
    _resultsScroll.addListener(() {
      if (_tabs.index == RoomSearchSection.messages.index &&
          _resultsScroll.hasClients &&
          _resultsScroll.position.extentAfter < 400) {
        unawaited(_loadOlder());
      }
    });
    _tabs = TabController(
      length: RoomSearchSection.values.length,
      vsync: this,
      initialIndex: widget.initialSection.index,
    )..addListener(_tabChanged);
    _lastTab = widget.initialSection.index;
    if (widget.initialSection != RoomSearchSection.messages) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goPage(0));
    }
  }

  void _tabChanged() {
    if (_tabs.indexIsChanging || _lastTab == _tabs.index) return;
    _lastTab = _tabs.index;
    _queryGeneration++;
    _debounce?.cancel();
    _page = 0;
    _serverResults = const [];
    _searchStopped = false;
    if (_loadingOlder || _navigating) _reloadTabAfterRequest = true;
    if (_query.text.trim().isNotEmpty) {
      _search();
    } else if (_kind != null) {
      _goPage(0);
    }
    if (mounted) setState(() {});
  }

  void _queryChanged(String value) {
    _page = 0;
    _searchStopped = false;
    _queryGeneration++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
    setState(() {});
  }

  Future<void> _search() async {
    final generation = _queryGeneration;
    final value = _query.text.trim();
    if (value.isEmpty) {
      setState(() {
        _serverResults = const [];
        _searching = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final found = await widget.backend.searchRoomHistory(
        _kind == null ? value : '$value has:${_kind!}',
      );
      if (mounted && generation == _queryGeneration) {
        setState(() => _serverResults = found);
      }
    } catch (_) {
      if (mounted && generation == _queryGeneration) {
        setState(() => _error = 'Search failed. Try again.');
      }
    } finally {
      if (mounted && generation == _queryGeneration) {
        setState(() => _searching = false);
        if (_kind == null &&
            !_searchStopped &&
            _error == null &&
            _serverResults.isEmpty &&
            _canLoadOlder) {
          _debounce = Timer(const Duration(milliseconds: 200), () {
            if (mounted && generation == _queryGeneration) _loadOlder();
          });
        }
      }
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _searching || !_canLoadOlder) {
      return;
    }
    setState(() => _loadingOlder = true);
    final generation = _queryGeneration;
    final section = _tabs.index;
    final kind = _kind;
    try {
      if (_query.text.trim().isEmpty) {
        if (kind != null) {
          final found = await widget.backend.loadMoreCatalog(
            widget.backend.selectedRoom?.id ?? '',
            kind,
          );
          if (mounted &&
              generation == _queryGeneration &&
              section == _tabs.index) {
            setState(() => _catalogResults[section] = found);
          }
        } else {
          await widget.backend.loadMoreHistory();
        }
      }
      _paginationPasses++;
      if (_query.text.trim().isNotEmpty) await _search();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load older messages. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
      if (_reloadTabAfterRequest && mounted) {
        _reloadTabAfterRequest = false;
        Future<void>.delayed(Duration.zero, () {
          if (mounted) {
            if (_query.text.trim().isNotEmpty) {
              _search();
            } else if (_kind != null) {
              _goPage(0);
            }
          }
        });
      }
    }
  }

  void _addFilter(String filter) {
    final current = _query.text.trim();
    _query.text = current.isEmpty ? '$filter ' : '$current $filter ';
    _query.selection = TextSelection.collapsed(offset: _query.text.length);
    _queryChanged(_query.text);
  }

  Future<void> _chooseSender() async {
    final people = widget.backend.selectedRoomMembers;
    final box = _fromKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin =
        box?.localToGlobal(Offset.zero, ancestor: overlay) ??
        const Offset(12, 100);
    FocusScope.of(context).unfocus();
    final selected = await showMenu<RoomMemberSummary>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + (box?.size.height ?? 0),
          box?.size.width ?? 100,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        if (people.isEmpty)
          const PopupMenuItem(
            enabled: false,
            child: Text('No room members loaded yet.'),
          ),
        for (final member in people)
          PopupMenuItem(
            value: member,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.displayName),
                Text(
                  member.userId,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
    if (selected == null || !mounted) return;
    _query.text = _query.text.replaceAll(RegExp(r'(^|\s)from:\S*'), '').trim();
    _addFilter('from:${selected.userId}');
  }

  Future<void> _goPage(int page) async {
    if (_navigating || _loadingOlder || page < 0) return;
    final generation = _queryGeneration;
    setState(() {
      _navigating = true;
      _error = null;
    });
    try {
      // Metadata is fetched only for an explicit page action, never as a side
      // effect of scrolling. Bound each action when matching media is sparse.
      for (
        var pass = 0;
        pass < 4 && _results.length < (page + 1) * _pageSize && _canLoadOlder;
        pass++
      ) {
        if (!mounted || generation != _queryGeneration) return;
        await _loadOlder();
      }
      if (!mounted || generation != _queryGeneration) return;
      if (page == 0 || page * _pageSize < _results.length) {
        setState(() => _page = page);
        if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
      } else if (_canLoadOlder) {
        setState(
          () => _error =
              'More history is needed to reach page ${page + 1}. Try Next or choose a loaded page.',
        );
      }
    } finally {
      if (mounted) setState(() => _navigating = false);
    }
  }

  Future<void> _jumpPage() async {
    final input = TextEditingController(text: '${_page + 1}');
    final page = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Page number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(input.text);
              if (n != null && n > 0 && n <= 100000) {
                Navigator.pop(context, n - 1);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    // The route may still be animating with its editor attached.
    if (page != null && mounted) await _goPage(page);
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
  }

  List<ChatMessage> get _results {
    final byId = <String, ChatMessage>{
      for (final message
          in _kind != null && _query.text.trim().isEmpty
              ? [
                  ...widget.backend.catalogMessagesForRoom(
                    widget.backend.selectedRoom?.id ?? '',
                    _kind!,
                  ),
                  ...?_catalogResults[_tabs.index],
                ]
              : widget.backend.messages)
        message.id: message,
      for (final message in _serverResults) message.id: message,
    };
    final query = _query.text.trim();
    final section = RoomSearchSection.values[_tabs.index];
    final results = byId.values.where((message) {
      if (query.isNotEmpty &&
          !matchesMessageSearch(
            body: message.body,
            formattedBody: message.formattedBody,
            sender: message.sender,
            senderId: message.senderId,
            roomName: widget.backend.selectedRoom?.name,
            timestamp: message.timestamp,
            attachment: message.attachment,
            query: query,
          )) {
        return false;
      }
      return switch (section) {
        RoomSearchSection.messages => true,
        RoomSearchSection.media =>
          message.attachment?.kind == AttachmentKind.image ||
              message.attachment?.kind == AttachmentKind.video,
        RoomSearchSection.files =>
          message.attachment != null &&
              message.attachment?.kind != AttachmentKind.image &&
              message.attachment?.kind != AttachmentKind.video,
        RoomSearchSection.links => catalogMatches(message, 'link'),
      };
    }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  @override
  void dispose() {
    _resultsScroll.dispose();
    _debounce?.cancel();
    _tabs.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = _results;
    final catalog = _kind != null;
    final results = catalog
        ? all.skip(_page * _pageSize).take(_pageSize).toList()
        : all;
    final media = _tabs.index == RoomSearchSection.media.index;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: TextField(
              controller: _query,
              autofocus: widget.initialSection == RoomSearchSection.messages,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search this room',
                suffixIcon: Icon(Icons.tune),
              ),
              onChanged: _queryChanged,
              onSubmitted: (_) => _search(),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final filter in const [
                  'from:',
                  'before:',
                  'after:',
                  'has:image',
                  'has:file',
                  'has:link',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      key: filter == 'from:' ? _fromKey : null,
                      visualDensity: VisualDensity.compact,
                      label: Text(filter),
                      onPressed: filter == 'from:'
                          ? _chooseSender
                          : () => _addFilter(filter),
                    ),
                  ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Messages'),
              Tab(text: 'Media'),
              Tab(text: 'Files'),
              Tab(text: 'Links'),
            ],
          ),
          if (_searching || _loadingOlder || _navigating)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Text(
                      _paginationPasses == 0
                          ? 'No matching loaded messages.'
                          : 'No matching messages found.',
                      style: TextStyle(color: context.deltiecord.muted),
                    ),
                  )
                : media
                ? GridView.builder(
                    controller: _resultsScroll,
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: results.length,
                    itemBuilder: (context, index) => _MediaResult(
                      key: ValueKey(results[index].id),
                      backend: widget.backend,
                      message: results[index],
                      onOpen: widget.onOpen,
                    ),
                  )
                : ListView.builder(
                    controller: _resultsScroll,
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final message = results[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(message.sender),
                        subtitle: Text(
                          message.attachment?.name ?? message.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          await widget.onOpen(message.id);
                        },
                      );
                    },
                  ),
          ),
          if (_searching ||
              (_serverResults.isEmpty &&
                  _canLoadOlder &&
                  !_searchStopped &&
                  _query.text.trim().isNotEmpty))
            TextButton(
              onPressed: () {
                _debounce?.cancel();
                setState(() => _searchStopped = true);
              },
              child: const Text('Stop searching older messages'),
            ),
          if (catalog)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                children: [
                  Text(
                    'Items ${results.isEmpty ? 0 : _page * _pageSize + 1} to ${_page * _pageSize + results.length} (${all.length} loaded)',
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: _navigating || _page == 0
                            ? null
                            : () => _goPage(_page - 1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      TextButton(
                        onPressed: _navigating ? null : _jumpPage,
                        child: Text('Page ${_page + 1}'),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed:
                            _navigating ||
                                (_page + 1) * _pageSize >= all.length &&
                                    !_canLoadOlder
                            ? null
                            : () => _goPage(_page + 1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!catalog && _canLoadOlder)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: OutlinedButton.icon(
                onPressed: _loadingOlder ? null : _loadOlder,
                icon: const Icon(Icons.history),
                label: Text(
                  _paginationPasses == 0
                      ? 'Search older messages'
                      : 'Load older results',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaResult extends StatefulWidget {
  const _MediaResult({
    required this.backend,
    required this.message,
    required this.onOpen,
    super.key,
  });

  final ChatBackend backend;
  final ChatMessage message;
  final Future<void> Function(String eventId) onOpen;
  @override
  State<_MediaResult> createState() => _MediaResultState();
}

class _MediaResultState extends State<_MediaResult> {
  ChatBackend get backend => widget.backend;
  ChatMessage get message => widget.message;
  Future<Uint8List?>? _pending;
  @override
  void didUpdateWidget(_MediaResult oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != backend ||
        oldWidget.message.id != message.id ||
        oldWidget.message.attachment?.sourceEventId !=
            message.attachment?.sourceEventId ||
        oldWidget.message.attachment?.hasThumbnail !=
            message.attachment?.hasThumbnail) {
      _pending = null;
    }
  }

  Future<Uint8List?> _thumbnail() async {
    final attachment = message.attachment;
    if (attachment == null) return null;
    // Browsing never fetches an original merely to produce a grid preview.
    if (!attachment.hasThumbnail) return null;
    final useThumbnail = attachment.hasThumbnail;
    final size = useThumbnail ? attachment.thumbnailSize : attachment.size;
    final width = useThumbnail ? attachment.thumbnailWidth : attachment.width;
    final height = useThumbnail
        ? attachment.thumbnailHeight
        : attachment.height;
    if (size == null ||
        size <= 0 ||
        size > 2 * 1024 * 1024 ||
        width == null ||
        height == null ||
        width <= 0 ||
        height <= 0 ||
        width > 4096 ||
        height > 4096 ||
        width * height > 8000000) {
      return null;
    }
    final bytes = await backend.downloadAttachment(
      message.id,
      thumbnail: useThumbnail,
    );
    return bytes.length <= 2 * 1024 * 1024 ? bytes : null;
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            MobileMediaGallery(backend: backend, initialMessage: message),
      );
    },
    onLongPress: () async {
      Navigator.pop(context);
      await widget.onOpen(message.id);
    },
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: context.deltiecord.elevated,
        child: FutureBuilder<Uint8List?>(
          future: _pending ??= _thumbnail(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return LifecycleMemoryImage(
                bytes: snapshot.data!,
                fit: BoxFit.cover,
                decodeWidth: 256,
                animated: message.attachment?.animated ?? false,
                autoplay: false,
              );
            }
            return Center(
              child: Icon(
                message.attachment?.kind == AttachmentKind.video
                    ? Icons.play_circle_outline
                    : Icons.image_outlined,
                size: 38,
              ),
            );
          },
        ),
      ),
    ),
  );
}
