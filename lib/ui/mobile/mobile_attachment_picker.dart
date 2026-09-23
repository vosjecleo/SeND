import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mime/mime.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/chat_models.dart';
import '../deltiecord_theme.dart';

/// Pages thumbnails only; original bytes are read after explicit selection.
class MobileAttachmentPicker extends StatefulWidget {
  const MobileAttachmentPicker({super.key});

  @override
  State<MobileAttachmentPicker> createState() => _MobileAttachmentPickerState();
}

class _MobileAttachmentPickerState extends State<MobileAttachmentPicker> {
  final _assets = <AssetEntity>[];
  final _selected = <AssetEntity>[];
  final _scroll = ScrollController();
  AssetPathEntity? _album;
  int _page = 0;
  bool _loading = true;
  bool _more = true;
  bool _reading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500) _loadMore();
    });
    _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _error =
            'Use Picker below to choose photos and videos from your device.';
      });
      return;
    }
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!mounted) return;
      if (!permission.hasAccess) {
        setState(() {
          _loading = false;
          _error = 'Allow photo access to browse here, or use Picker below.';
        });
        return;
      }
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        onlyAll: true,
      );
      if (!mounted) return;
      _album = albums.firstOrNull;
      _loading = false;
      await _loadMore();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not open photos. You can still use Picker below.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_more || !mounted) return;
    final album = _album;
    if (album == null) {
      setState(() => _more = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final items = await album.getAssetListPaged(page: _page, size: 60);
      if (!mounted) return;
      setState(() {
        _assets.addAll(items);
        _page++;
        _more = items.length == 60;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load more photos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _attach() async {
    if (_reading) return;
    setState(() => _reading = true);
    try {
      final drafts = <AttachmentDraft>[];
      var total = 0;
      for (final asset in _selected) {
        final file = await asset.originFile;
        if (file == null) throw StateError('One selected item is unavailable.');
        total += await file.length();
        if (total > 64 * 1024 * 1024) {
          throw StateError('Select fewer items (64 MiB per selection).');
        }
        final bytes = await file.readAsBytes();
        final name = await asset.titleAsync;
        drafts.add(
          AttachmentDraft(
            bytes: bytes,
            name: name.isEmpty ? file.uri.pathSegments.last : name,
            mimeType:
                lookupMimeType(file.path, headerBytes: bytes) ??
                'application/octet-stream',
            spoiler: false,
          ),
        );
      }
      if (mounted) Navigator.pop(context, drafts);
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not read the selected media.');
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 12),
            const Expanded(child: Text('Photos and videos')),
            if (_selected.isNotEmpty)
              TextButton(
                onPressed: _reading ? null : _attach,
                child: Text(
                  _reading ? 'Loading…' : 'Attach (${_selected.length})',
                ),
              ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
        Expanded(
          child: Stack(
            children: [
              GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 88),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: _assets.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Material(
                      color: context.deltiecord.island,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, 'camera-photo'),
                        onLongPress: () =>
                            Navigator.pop(context, 'camera-video'),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 36),
                            Text('Camera'),
                            Text(
                              'Hold for video',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final asset = _assets[index - 1];
                  return _PhotoTile(
                    key: ValueKey(asset.id),
                    asset: asset,
                    selected: _selected.contains(asset),
                    onTap: _reading
                        ? null
                        : () => setState(() {
                            if (!_selected.remove(asset) &&
                                _selected.length < 20) {
                              _selected.add(asset);
                            }
                          }),
                  );
                },
              ),
              if (_loading)
                const Align(
                  alignment: Alignment.topCenter,
                  child: LinearProgressIndicator(),
                ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Center(
                  child: Material(
                    elevation: 4,
                    color: context.deltiecord.island,
                    borderRadius: DeltiecordCorners.borderRadius,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (action, label, icon) in [
                          ('media', 'Picker', Icons.photo_library_outlined),
                          ('poll', 'Poll', Icons.poll_outlined),
                          ('file', 'Files', Icons.attach_file),
                        ])
                          Flexible(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: _reading
                                  ? null
                                  : () => Navigator.pop(context, action),
                              icon: Icon(icon, size: 20),
                              label: Text(
                                label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.asset,
    required this.selected,
    required this.onTap,
    super.key,
  });
  final AssetEntity asset;
  final bool selected;
  final VoidCallback? onTap;
  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late final Future<Uint8List?> _thumbnail = widget.asset.thumbnailDataWithSize(
    const ThumbnailSize.square(240),
  );
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: widget.onTap,
    child: Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Uint8List?>(
          future: _thumbnail,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            return bytes == null
                ? ColoredBox(color: context.deltiecord.island)
                : Image.memory(bytes, fit: BoxFit.cover);
          },
        ),
        if (widget.asset.type == AssetType.video)
          const Align(
            alignment: Alignment.bottomLeft,
            child: Icon(Icons.play_arrow, color: Colors.white),
          ),
        Align(
          alignment: Alignment.topRight,
          child: Icon(
            widget.selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: widget.selected
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
          ),
        ),
      ],
    ),
  );
}
