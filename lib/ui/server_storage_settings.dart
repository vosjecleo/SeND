import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../services/server_storage.dart';

const _storageKinds = {
  'images': ('Images', Colors.blue),
  'videos': ('Videos', Colors.deepPurple),
  'gifs': ('GIFs', Colors.pink),
  'audio': ('Audio', Colors.orange),
  'legacy': ('Legacy', Colors.grey),
  'other': ('Other', Colors.blueGrey),
};
String storageSize(num bytes) => bytes >= 1073741824
    ? '${(bytes / 1073741824).toStringAsFixed(2)} GiB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MiB';

class _StorageSegment extends StatefulWidget {
  const _StorageSegment({
    required this.id,
    required this.label,
    required this.bytes,
    required this.color,
    required this.hoverEnabled,
  });
  final String id, label;
  final num bytes;
  final Color color;
  final bool hoverEnabled;
  @override
  State<_StorageSegment> createState() => _StorageSegmentState();
}

class _StorageSegmentState extends State<_StorageSegment> {
  final _overlay = OverlayPortalController();
  Offset _cursor = Offset.zero;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final highlight = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final fill = DecoratedBox(
      key: ValueKey('storage-segment-fill-${widget.id}'),
      decoration: BoxDecoration(
        color: _hovered
            ? Color.alphaBlend(highlight.withValues(alpha: .2), widget.color)
            : widget.color,
        border: _hovered
            ? Border.all(color: highlight.withValues(alpha: .55))
            : null,
      ),
      child: const SizedBox.expand(),
    );
    if (!widget.hoverEnabled) return fill;
    return MouseRegion(
      key: ValueKey('storage-segment-${widget.id}'),
      onEnter: (event) {
        setState(() {
          _hovered = true;
          _cursor = event.position;
        });
        _overlay.show();
      },
      onHover: (event) => setState(() => _cursor = event.position),
      onExit: (_) {
        setState(() => _hovered = false);
        _overlay.hide();
      },
      child: OverlayPortal(
        overlayLocation: OverlayChildLocation.rootOverlay,
        controller: _overlay,
        overlayChildBuilder: (context) {
          final root =
              Overlay.of(context, rootOverlay: true).context.findRenderObject()
                  as RenderBox;
          return Positioned.fill(
            child: IgnorePointer(
              child: CustomSingleChildLayout(
                delegate: _CursorStorageLabel(root.globalToLocal(_cursor)),
                child: Material(
                  key: const ValueKey('storage-category-tooltip'),
                  elevation: 4,
                  borderRadius: BorderRadius.circular(6),
                  color: Theme.of(context).colorScheme.inverseSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Text(
                      '${widget.label}: ${storageSize(widget.bytes)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: fill,
      ),
    );
  }
}

class _CursorStorageLabel extends SingleChildLayoutDelegate {
  _CursorStorageLabel(this.cursor);
  final Offset cursor;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();
  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final top = cursor.dy + 18 + childSize.height <= size.height - 8
        ? cursor.dy + 18
        : cursor.dy - childSize.height - 12;
    return Offset(
      (cursor.dx + 14)
          .clamp(0, (size.width - childSize.width).clamp(0, double.infinity))
          .toDouble(),
      top
          .clamp(0, (size.height - childSize.height).clamp(0, double.infinity))
          .toDouble(),
    );
  }

  @override
  bool shouldRelayout(covariant _CursorStorageLabel oldDelegate) =>
      cursor != oldDelegate.cursor;
}

class ServerStorageSettings extends StatefulWidget {
  const ServerStorageSettings({required this.backend, super.key});
  final ChatBackend backend;
  @override
  State<ServerStorageSettings> createState() => _ServerStorageSettingsState();
}

class _ServerStorageSettingsState extends State<ServerStorageSettings> {
  Map<String, dynamic>? _usage;
  String? _error, _notice;
  bool _busy = false;
  String _kind = 'videos', _source = 'all';
  int _days = 180;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final usage = normalizeServerStorageUsage(
        await widget.backend.serverStorage('usage'),
      );
      if (usage['used_bytes'] is! num ||
          usage['quota_bytes'] is! num ||
          usage['categories'] is! Map) {
        throw const FormatException();
      }
      if (mounted) _usage = usage;
    } on UnsupportedError {
      if (mounted) {
        _error = 'Your homeserver does not support SeND storage controls.';
      }
    } catch (_) {
      if (mounted) {
        _error =
            'Could not load server storage. Check your connection and try again.';
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _prune() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final preview = await widget.backend.serverStorage('prune-preview', {
        'before': DateTime.now()
            .subtract(Duration(days: _days))
            .millisecondsSinceEpoch,
        'kind': _kind,
        if (_source != 'all') 'source': _source,
      });
      final files = preview['files'];
      if (files is! List ||
          preview['bytes'] is! num ||
          preview['token'] is! String) {
        throw const FormatException();
      }
      if (!mounted) return;
      if (files.isEmpty) {
        _notice = 'No matching uploads.';
        return;
      }
      setState(() => _busy = false);
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Delete ${files.length} uploads?'),
          content: Text(
            'Delete ${storageSize(preview['bytes'] as num)} from your homeserver? Shared attachments will stop working; messages stay. This can\'t be undone, and copies elsewhere may remain.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete uploads'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      setState(() => _busy = true);
      final result = await widget.backend.serverStorage('prune', {
        'token': preview['token'],
        'confirm': true,
      });
      if (mounted) {
        _notice = result['dry_run'] == true
            ? 'Preview: ${result['would_delete']} uploads would be deleted. Nothing was removed.'
            : '${result['deleted']} uploads deleted.';
      }
      await _load();
    } catch (_) {
      if (mounted) {
        _error =
            'Could not finish pruning. Refresh storage before trying again.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    final mobile =
        MediaQuery.sizeOf(context).width < 600 ||
        {
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(Theme.of(context).platform);
    final legend = usage == null
        ? ''
        : _storageKinds.entries
              .map(
                (entry) =>
                    '${entry.value.$1}: ${storageSize(((usage['categories'] as Map)[entry.key] as Map?)?['bytes'] as num? ?? 0)}',
              )
              .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (usage != null) ...[
          if (usage['quota_enforced'] == false)
            const Text('Preview only — storage limits aren\'t enforced.'),
          if (usage['dry_run_pruning'] == true)
            const Text('Preview only — nothing will be deleted.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Categorize encrypted uploads'),
            subtitle: const Text(
              'Shares upload types and GIF sources with your homeserver, not messages, filenames or encryption keys.',
            ),
            value: widget.backend.preferences.shareUploadCategories,
            onChanged: _busy
                ? null
                : (value) async {
                    setState(() {
                      _busy = true;
                      _error = null;
                    });
                    try {
                      await widget.backend.updatePreferences(
                        widget.backend.preferences.copyWith(
                          shareUploadCategories: value,
                        ),
                      );
                      if (mounted) await _load();
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => _error =
                              'Could not change upload categorization. Try again.',
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
          ),
          Text(
            '${storageSize(usage['used_bytes'] as num)} of ${storageSize(usage['quota_bytes'] as num)} used',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${storageSize(usage['remaining_bytes'] as num? ?? 0)} remaining',
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Server media usage by category. $legend',
            child: SizedBox(
              height: 28,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final categories = usage['categories'] as Map;
                    final quota = (usage['quota_bytes'] as num).toDouble();
                    final used = (usage['used_bytes'] as num).toDouble();
                    final total = (used > quota ? used : quota).clamp(
                      1,
                      double.infinity,
                    );
                    return Row(
                      children: [
                        for (final entry in _storageKinds.entries)
                          SizedBox(
                            width:
                                constraints.maxWidth *
                                (((categories[entry.key] as Map?)?['bytes']
                                            as num? ??
                                        0) /
                                    total),
                            child: _StorageSegment(
                              id: entry.key,
                              label: entry.value.$1,
                              bytes:
                                  (categories[entry.key] as Map?)?['bytes']
                                      as num? ??
                                  0,
                              hoverEnabled: !mobile,
                              color: entry.value.$2,
                            ),
                          ),
                        Expanded(
                          child: _StorageSegment(
                            id: 'available',
                            label: 'Available',
                            bytes: usage['remaining_bytes'] as num? ?? 0,
                            hoverEnabled: !mobile,
                            color: Color(0x22777777),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          if (mobile) const SizedBox(height: 8),
          if (mobile)
            for (final entry in _storageKinds.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.circle, color: entry.value.$2, size: 10),
                    const SizedBox(width: 8),
                    Expanded(child: Text(entry.value.$1)),
                    Text(
                      storageSize(
                        ((usage['categories'] as Map)[entry.key]
                                    as Map?)?['bytes']
                                as num? ??
                            0,
                      ),
                    ),
                  ],
                ),
              ),

          const Divider(height: 32),
          Text(
            'Prune old uploads',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Media type'),
            items: [
              for (final entry in _storageKinds.entries.where(
                (entry) =>
                    entry.key != 'legacy' || usage['legacy_pruning'] == true,
              ))
                DropdownMenuItem(value: entry.key, child: Text(entry.value.$1)),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _kind = v!;
                    if (v == 'legacy') _source = 'all';
                  }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _days,
            decoration: const InputDecoration(labelText: 'Older than'),
            items: [
              for (final days in [30, 90, 180, 365])
                DropdownMenuItem(value: days, child: Text('$days days')),
            ],
            onChanged: _busy ? null : (v) => setState(() => _days = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _source,
            decoration: const InputDecoration(labelText: 'Source'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All uploads')),
              DropdownMenuItem(value: 'upload', child: Text('Uploaded files')),
              DropdownMenuItem(value: 'klipy', child: Text('Klipy GIFs')),
            ],
            onChanged: _busy || _kind == 'legacy'
                ? null
                : (v) => setState(() => _source = v!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _prune,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Preview files to delete'),
          ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        if (_notice != null) Text(_notice!),
        if (widget.backend.serverStorageWarning case final warning?)
          Text(warning),
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Refresh server storage'),
        ),
      ],
    );
  }
}
