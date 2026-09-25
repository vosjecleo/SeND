part of 'advanced_chat_dialogs.dart';

class _PackEditItem {
  _PackEditItem(this.value) : alias = value.shortcode;
  StickerDraftItem value;
  String alias;
  bool selected = false;
  _PackEditItem copy() => _PackEditItem(value)
    ..alias = alias
    ..selected = selected;
  StickerDraftItem get draft => StickerDraftItem(
    shortcode: alias.trim(),
    bytes: value.bytes,
    mimeType: value.mimeType,
    width: value.width,
    height: value.height,
    assetType: value.assetType,
    reuse: value.reuse,
  );
}

/// An edit session changes metadata independently of media. Unchanged items
/// retain MXC identity; only explicitly added/cropped items are uploaded.
class StickerPackEditor extends StatefulWidget {
  const StickerPackEditor({
    required this.backend,
    required this.pack,
    super.key,
  });
  final ChatBackend backend;
  final StickerPackSummary pack;
  @override
  State<StickerPackEditor> createState() => _StickerPackEditorState();
}

class _StickerPackEditorState extends State<StickerPackEditor> {
  late final _name = TextEditingController(text: widget.pack.name);
  late List<_PackEditItem> _items = widget.pack.stickers
      .map((item) => _PackEditItem(packItemReference(item)))
      .toList();
  List<_PackEditItem>? _undo;
  bool _busy = false;
  String? _error;
  String _progress = '';
  void _checkpoint() => _undo = _items.map((item) => item.copy()).toList();

  Future<void> _merge() async {
    final candidates = widget.backend.stickerPacks
        .where(
          (pack) =>
              pack.id != widget.pack.id ||
              pack.sourceRoomId != widget.pack.sourceRoomId,
        )
        .toList();
    final pack = await showModalBottomSheet<StickerPackSummary>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Merge another pack into this one'),
              subtitle: Text(
                'Original packs stay available. Duplicate aliases receive a numbered suffix. Save changes to finish.',
              ),
            ),
            if (candidates.isEmpty)
              const ListTile(title: Text('No other packs available')),
            for (final pack in candidates)
              ListTile(
                title: Text(pack.name),
                subtitle: Text('${pack.stickers.length} items'),
                onTap: () => Navigator.pop(context, pack),
              ),
          ],
        ),
      ),
    );
    if (!mounted || pack == null) return;
    try {
      final combined = mergePackItems(
        _items.map((item) => item.draft).toList(),
        pack.stickers,
      );
      setState(() {
        _checkpoint();
        _items = combined.map(_PackEditItem.new).toList();
        _error = null;
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  Future<void> _split() async {
    if (!_validate()) return;
    final selected = _items.where((item) => item.selected).toList();
    if (selected.isEmpty || selected.length == _items.length) {
      setState(
        () => _error =
            'Select some items, leaving at least one in the original pack.',
      );
      return;
    }
    final baseName = _name.text.trim();
    var name = '${baseName.substring(0, min(baseName.length, 72))} — split';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Split selected into a new personal pack'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The new pack is saved first, then these items are removed from the original. Other edits are saved too. If the second save fails, both copies are kept.',
              ),
              TextFormField(
                initialValue: name,
                maxLength: 80,
                onChanged: (value) => name = value,
                decoration: const InputDecoration(labelText: 'New pack name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Split pack'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    if (name.trim().isEmpty || name.trim().length > 80) {
      setState(() => _error = 'The new pack needs a name of 1–80 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Saving new pack…';
    });
    try {
      await widget.backend.savePersonalStickerPack(
        StickerPackDraft(
          name: name.trim(),
          stickers: selected.map((item) => item.draft).toList(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _items.removeWhere(selected.contains);
        _undo = null;
      });
      await _save();
      if (mounted && _error != null) {
        setState(
          () => _error =
              'New pack saved. The original is unchanged: $_error Retry Save changes to finish the split.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add(StickerAssetType type) async {
    try {
      final picked = await _pickStickerImages();
      if (!mounted || picked == null) return;
      if (_items.length + picked.length > StickerPackDraft.maximumItems) {
        throw StateError('A pack can contain at most 150 items.');
      }
      final prepared = type == StickerAssetType.emoji
          ? await _prepareEmojiItems(context, picked)
          : _asAssetType(picked, type);
      if (!mounted || prepared == null) return;
      setState(() {
        _checkpoint();
        final used = _items.map((item) => item.alias.toLowerCase()).toSet();
        for (final value in prepared) {
          final entry = _PackEditItem(value);
          final base = entry.alias.isEmpty
              ? 'image'
              : entry.alias.substring(0, min(90, entry.alias.length));
          entry.alias = base;
          for (var n = 2; used.contains(entry.alias.toLowerCase()); n++) {
            entry.alias = '${base}_$n';
          }
          used.add(entry.alias.toLowerCase());
          _items.add(entry);
        }
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<StickerDraftItem> _load(_PackEditItem item) async {
    final value = item.draft;
    final bytes = value.bytes.isNotEmpty
        ? value.bytes
        : await widget.backend.loadStickerPreview(value.reuse!);
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'Could not load ${item.alias}. Retry without losing your edits.',
      );
    }
    return StickerDraftItem(
      shortcode: value.shortcode,
      bytes: bytes,
      mimeType: value.mimeType,
      assetType: value.assetType,
    );
  }

  Future<void> _crop() async {
    final selected = _items.where((item) => item.selected).toList();
    if (selected.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Loading crop preview…';
    });
    try {
      final first = await _load(selected.first);
      if (!mounted) return;
      final choice = await showDialog<_PackCropChoice>(
        context: context,
        builder: (_) => _PackCropDialog(
          item: first,
          emoji: selected.any(
            (item) => item.value.assetType == StickerAssetType.emoji,
          ),
        ),
      );
      if (choice == null || !mounted) return;
      final changed = <StickerDraftItem>[];
      for (var index = 0; index < selected.length; index++) {
        if (!mounted) return;
        setState(
          () => _progress = 'Preparing ${index + 1} of ${selected.length}…',
        );
        final input = index == 0 ? first : await _load(selected[index]);
        final result = await compute(_preparePackCrop, (input, choice));
        changed.add(
          StickerDraftItem(
            shortcode: input.shortcode,
            bytes: result.bytes,
            mimeType: result.mimeType,
            width: result.width,
            height: result.height,
            assetType: input.assetType,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _checkpoint();
        for (var i = 0; i < selected.length; i++) {
          selected[i].value = changed[i];
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validate() {
    final name = _name.text.trim();
    final aliases = _items.map((item) => item.alias.trim()).toList();
    if (name.isEmpty ||
        name.length > 80 ||
        _items.isEmpty ||
        aliases.any(
          (name) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$').hasMatch(name),
        ) ||
        aliases.map((name) => name.toLowerCase()).toSet().length !=
            aliases.length) {
      setState(
        () => _error =
            'Use a pack name, keep at least one item and give each item a unique alias (letters, numbers, underscores or hyphens).',
      );
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    final name = _name.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Saving changed items…';
    });
    try {
      await widget.backend.replaceStickerPack(
        widget.pack,
        StickerPackDraft(
          name: name,
          stickers: _items.map((item) => item.draft).toList(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelected = _items.any((item) => item.selected);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Text(
                            'Edit pack',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          TextField(
                            key: const ValueKey('pack-editor-name'),
                            controller: _name,
                            enabled: !_busy,
                            maxLength: 80,
                            decoration: const InputDecoration(
                              labelText: 'Pack name',
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              PopupMenuButton<StickerAssetType>(
                                enabled: !_busy,
                                onSelected: _add,
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: StickerAssetType.sticker,
                                    child: Text('Add stickers'),
                                  ),
                                  PopupMenuItem(
                                    value: StickerAssetType.emoji,
                                    child: Text('Add emojis'),
                                  ),
                                ],
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Add images'),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _merge,
                                child: const Text('Merge pack'),
                              ),
                              TextButton(
                                onPressed: _busy || !hasSelected
                                    ? null
                                    : _split,
                                child: const Text('Split selected'),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        final all = _items.every(
                                          (item) => item.selected,
                                        );
                                        for (final item in _items) {
                                          item.selected = !all;
                                        }
                                      }),
                                child: const Text('Select / clear all'),
                              ),
                              TextButton(
                                onPressed: _busy || !hasSelected ? null : _crop,
                                child: const Text('Crop / resize selected'),
                              ),
                              TextButton(
                                onPressed: _busy || !hasSelected
                                    ? null
                                    : () => setState(() {
                                        _checkpoint();
                                        _items.removeWhere(
                                          (item) => item.selected,
                                        );
                                      }),
                                child: const Text('Remove selected'),
                              ),
                              TextButton(
                                onPressed: _busy || _undo == null
                                    ? null
                                    : () => setState(() {
                                        _items = _undo!;
                                        _undo = null;
                                      }),
                                child: const Text('Undo'),
                              ),
                            ],
                          ),
                          Text(
                            '${_items.length}/150 items · aliases and removals do not re-upload media',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (_busy) ...[
                            const LinearProgressIndicator(),
                            Text(_progress),
                          ],
                          if (_error != null)
                            Text(
                              _error!,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final entry = _items[index], item = entry.value;
                        return Padding(
                          key: ObjectKey(entry),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Checkbox(
                                value: entry.selected,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(
                                        () => entry.selected = value!,
                                      ),
                              ),
                              SizedBox.square(
                                dimension: 48,
                                child: item.bytes.isNotEmpty
                                    ? LifecycleMemoryImage(
                                        bytes: item.bytes,
                                        animated: false,
                                        autoplay:
                                            widget
                                                .backend
                                                .preferences
                                                .autoplayGifs &&
                                            !widget
                                                .backend
                                                .preferences
                                                .reducedMotion,
                                      )
                                    : _StickerPreviewImage(
                                        backend: widget.backend,
                                        sticker: item.reuse!,
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: entry.alias,
                                  enabled: !_busy,
                                  onChanged: (value) => entry.alias = value,
                                  decoration: InputDecoration(
                                    labelText:
                                        item.assetType == StickerAssetType.emoji
                                        ? 'Emoji alias'
                                        : 'Sticker name',
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove item',
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                        _checkpoint();
                                        _items.remove(entry);
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      }, childCount: _items.length),
                    ),
                  ],
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const ValueKey('pack-editor-save'),
                    onPressed: _busy ? null : _save,
                    child: const Text('Save changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _PackCropChoice = ({
  int size,
  bool trim,
  CustomEmojiResizeFilter filter,
});
PreparedCustomEmoji _preparePackCrop(
  (StickerDraftItem, _PackCropChoice) request,
) => prepareCustomEmojiAsset(
  request.$1.bytes,
  request.$1.mimeType,
  filter: request.$2.filter,
  trimTransparentPadding: request.$2.trim,
  targetDimension: request.$2.size,
  forceResize: true,
  maximumBytes: request.$1.assetType == StickerAssetType.emoji
      ? StickerPackDraft.maximumEmojiBytes
      : 5 * 1024 * 1024,
);

class _PackCropDialog extends StatefulWidget {
  const _PackCropDialog({required this.item, required this.emoji});
  final StickerDraftItem item;
  final bool emoji;
  @override
  State<_PackCropDialog> createState() => _PackCropDialogState();
}

class _PackCropDialogState extends State<_PackCropDialog> {
  late int _size = widget.emoji ? 128 : 512;
  bool _trim = true;
  CustomEmojiResizeFilter _filter = CustomEmojiResizeFilter.bicubic;
  late Future<PreparedCustomEmoji> _preview = _render();
  _PackCropChoice get _choice => (size: _size, trim: _trim, filter: _filter);
  Future<PreparedCustomEmoji> _render() =>
      compute(_preparePackCrop, (widget.item, _choice));
  void _change(VoidCallback update) => setState(() {
    update();
    _preview = _render();
  });
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crop / resize selected'),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Preview of the first selected item. All selected items use these settings. Aspect ratio and animation are preserved; GIF conversion may reduce colours.',
          ),
          FutureBuilder<PreparedCustomEmoji>(
            future: _preview,
            builder: (context, result) => Column(
              children: [
                SizedBox.square(
                  dimension: 160,
                  child: result.hasData
                      ? LifecycleMemoryImage(
                          bytes: result.data!.bytes,
                          animated: false,
                          autoplay: !MediaQuery.disableAnimationsOf(context),
                        )
                      : result.hasError
                      ? const Icon(Icons.error_outline)
                      : const Center(child: CircularProgressIndicator()),
                ),
                if (result.hasError) Text('${result.error}'),
              ],
            ),
          ),
          DropdownButton<int>(
            value: _size,
            items: [
              for (final value
                  in widget.emoji ? [64, 96, 128] : [128, 256, 512])
                DropdownMenuItem(value: value, child: Text('$value × $value')),
            ],
            onChanged: (value) => _change(() => _size = value!),
          ),
          DropdownButton<CustomEmojiResizeFilter>(
            value: _filter,
            items: [
              for (final value in CustomEmojiResizeFilter.values)
                DropdownMenuItem(value: value, child: Text(value.name)),
            ],
            onChanged: (value) => _change(() => _filter = value!),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Trim transparent padding'),
            subtitle: const Text(
              'One shared crop across animation frames; no stretching.',
            ),
            value: _trim,
            onChanged: (value) => _change(() => _trim = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () async {
          try {
            await _preview;
            if (context.mounted) Navigator.pop(context, _choice);
          } catch (_) {
            /* Preview shows the error. */
          }
        },
        child: const Text('Apply to selected'),
      ),
    ],
  );
}
