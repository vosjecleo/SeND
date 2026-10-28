import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../services/server_storage.dart';

const _storageKinds = {
  'images': ('Images', Colors.blue),
  'videos': ('Videos', Colors.deepPurple),
  'gifs': ('GIFs', Colors.pink),
  'audio': ('Audio', Colors.orange),
  'other': ('Other', Colors.blueGrey),
};
String storageSize(num bytes) => bytes >= 1073741824
    ? '${(bytes / 1073741824).toStringAsFixed(2)} GiB'
    : '${(bytes / 1048576).toStringAsFixed(1)} MiB';

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
        _notice =
            'No matching uploads. Older unclassified files are not included in bulk pruning.';
        return;
      }
      setState(() => _busy = false);
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text('Delete ${files.length} uploads?'),
          content: Text(
            'Remove ${storageSize(preview['bytes'] as num)} from your homeserver. '
            'These attachments will stop working for everyone who received them. '
            'This cannot be undone. Messages stay in chat history. Copies on other servers or devices may remain. '
            'This preview includes at most 100 files; profile images and protected assets are excluded.',
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
            ? 'Preview only: ${result['would_delete']} uploads would be deleted. Nothing was removed.'
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Server storage', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (usage != null) ...[
          if (usage['quota_enforced'] == false)
            const Text(
              'The displayed allowance is not enforced during this preview.',
            ),
          if (usage['dry_run_pruning'] == true)
            const Text('Deletion is a dry run. No uploads will be removed.'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Categorize encrypted uploads'),
            subtitle: const Text(
              'Share upload types and GIF sources with your homeserver. Message text, filenames and encryption keys are not sent.',
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
            label: 'Server media usage by category',
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
                            child: ColoredBox(
                              color: entry.value.$2,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        const Expanded(
                          child: ColoredBox(
                            color: Color(0x22777777),
                            child: SizedBox.expand(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final entry in _storageKinds.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, color: entry.value.$2, size: 12),
              title: Text(entry.value.$1),
              trailing: Text(
                storageSize(
                  ((usage['categories'] as Map)[entry.key] as Map?)?['bytes']
                          as num? ??
                      0,
                ),
              ),
            ),
          const Text(
            'This is uploaded media, not your message database or local cache. '
            'Encrypted uploads without a type label appear under Other. '
            'Optional categorization shares media types and source labels with your homeserver, never message text or encryption keys.',
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
              for (final entry in _storageKinds.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value.$1)),
            ],
            onChanged: _busy ? null : (v) => setState(() => _kind = v!),
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
            onChanged: _busy ? null : (v) => setState(() => _source = v!),
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
