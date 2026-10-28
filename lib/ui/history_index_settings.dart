import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../backend/chat_backend.dart';
import '../services/history_index.dart';
import '../services/history_download.dart';
import '../services/history_scope.dart';
import 'history_download_panel.dart';

final _indexPrompts = Expando<bool>();

Future<void> showHistoryIndexPrompt(
  BuildContext context,
  ChatBackend backend,
) async {
  final index = await backend.openHistoryIndex();
  if (index == null ||
      index.prompted ||
      !context.mounted ||
      _indexPrompts[index] == true) {
    return;
  }
  _indexPrompts[index] = true;
  try {
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Keep a local search index?'),
        content: Text(
          'Save messages on this device for faster searches? ${index.encryptedAtRest ? '' : 'Message text will be stored unencrypted.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it off'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enable text index'),
          ),
        ],
      ),
    );
    if (enable != null) await backend.configureHistoryIndex(enable);
  } finally {
    _indexPrompts[index] = false;
  }
}

class HistoryIndexSettings extends StatefulWidget {
  const HistoryIndexSettings({required this.backend, super.key});
  final ChatBackend backend;
  @override
  State<HistoryIndexSettings> createState() => _HistoryIndexSettingsState();
}

class _HistoryIndexSettingsState extends State<HistoryIndexSettings> {
  HistoryIndex? _index;
  HistoryDownload? _download;
  bool _busy = true;
  int _scopeChoiceRevision = 0;
  String? _error;
  void _updated() {
    if (mounted) setState(() {});
  }

  void _bind(HistoryIndex? index) {
    _index?.removeListener(_updated);
    _index = index;
    index?.addListener(_updated);
  }

  @override
  void dispose() {
    _index?.removeListener(_updated);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _busy = true;
        _error = null;
      });
    }
    try {
      final index = await widget.backend.retryHistoryIndex();
      final download = index == null
          ? null
          : await widget.backend.openHistoryDownload();
      if (mounted) {
        setState(() {
          _bind(index);
          _download = download;
          if (index == null) {
            _error =
                widget.backend.historyIndexError ??
                'Local indexing is unavailable. Check storage and reopen Settings to retry.';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the local index.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _change(bool enabled, {int? limit, bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    var changed = false;
    try {
      if (clear) {
        await widget.backend.clearHistoryIndex();
      } else {
        await widget.backend.configureHistoryIndex(enabled, limitMiB: limit);
      }
      final index = await widget.backend.openHistoryIndex();
      if (mounted) setState(() => _bind(index));
      changed = true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update the index. Check available storage.',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
    return changed;
  }

  Future<void> _changeScope(HistoryScope scope) async {
    if (scope == _index?.scope) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change search scope?'),
        content: const Text(
          'Remove excluded messages from local search and reset download progress? Your chats and uploads won\'t be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change scope'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accepted != true) {
      setState(() => _scopeChoiceRevision++);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.configureHistoryScope(scope);
    } catch (_) {
      if (mounted) _error = 'Could not change the search scope. Try again.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _scopeChoiceRevision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Keep a local text search index'),
          subtitle: const Text(
            'Turning this off clears saved search text, not your chats.',
          ),
          value: index?.enabled ?? false,
          onChanged: _busy ? null : (v) => _change(v),
        ),

        if (index != null) ...[
          DropdownButtonFormField<HistoryScope>(
            key: ValueKey(
              'history-scope-${index.scope.name}-$_scopeChoiceRevision',
            ),
            initialValue: index.scope,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Keep history from'),
            items: [
              for (final scope in HistoryScope.values)
                DropdownMenuItem(value: scope, child: Text(scope.label)),
            ],
            onChanged: _busy
                ? null
                : (scope) {
                    if (scope != null) _changeScope(scope);
                  },
          ),
          const SizedBox(height: 12),
          Text(
            '${index.entries} events · ${(index.bytes / 1048576).toStringAsFixed(1)} MiB${kIsWeb ? ' estimated' : ''}',
          ),
          Text(
            '${(index.capacityRatio * 100).clamp(0, 100).toStringAsFixed(0)}% of storage limit used',
          ),
          DropdownButtonFormField<int>(
            initialValue: index.limitMiB,
            key: ValueKey(index.limitMiB),
            decoration: const InputDecoration(labelText: 'Index storage limit'),
            items: [
              for (final n in {
                25,
                50,
                100,
                250,
                500,
                1024,
                2048,
                index.limitMiB,
              }.toList()..sort())
                DropdownMenuItem(value: n, child: Text('$n MiB')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v != null) _change(index.enabled, limit: v);
                  },
          ),
          TextButton(
            onPressed: _busy ? null : () => _change(index.enabled, clear: true),
            child: const Text('Clear search and media index'),
          ),
          if (_download case final download?)
            HistoryDownloadPanel(
              backend: widget.backend,
              index: index,
              download: download,
              increaseLimit: (limit) => _change(true, limit: limit),
            ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Text(_error!),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Retry opening search storage'),
          ),
        ],
      ],
    );
  }
}

class HistoryIndexWarningGate extends StatefulWidget {
  const HistoryIndexWarningGate({
    required this.backend,
    required this.child,
    super.key,
  });
  final ChatBackend backend;
  final Widget child;
  @override
  State<HistoryIndexWarningGate> createState() =>
      _HistoryIndexWarningGateState();
}

class _HistoryIndexWarningGateState extends State<HistoryIndexWarningGate> {
  bool _showing = false, _scheduled = false;
  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(HistoryIndexWarningGate old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend) {
      old.backend.removeListener(_check);
      widget.backend.addListener(_check);
    }
    _check();
  }

  @override
  void dispose() {
    widget.backend.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_showing ||
        _scheduled ||
        widget.backend.historyIndex?.warningPending != true) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _scheduled = false;
      if (!mounted || _showing) return;
      final index = widget.backend.historyIndex;
      if (index == null || !index.warningPending) return;
      _showing = true;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Search cache almost full'),
          content: Text(
            'Search storage is 80% full. Older search results will be cleared as needed; your chats and uploads won\'t be deleted.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      try {
        await index.acknowledgeCapacityWarning();
      } catch (_) {}
      _showing = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
