import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../services/history_index.dart';

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
        content: const Text(
          'A text index makes repeat searches faster and uses extra storage on this device. '
          'It starts with a 100 MiB limit. You can change the limit or clear it in Storage settings. '
          'Media indexing saves event references, not the images or videos. '
          'Indexed message text is decrypted on this device. This is separate from the normal chat cache.',
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
  bool _busy = true;
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
      final index = await widget.backend.openHistoryIndex();
      if (mounted) {
        setState(() {
          _bind(index);
          if (index == null) {
            _error =
                'Local indexing is unavailable. Check storage and reopen Settings to retry.';
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the local index.');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _change(bool enabled, {int? limit, bool clear = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (clear) {
        await widget.backend.clearHistoryIndex();
      } else {
        await widget.backend.configureHistoryIndex(enabled, limitMiB: limit);
      }
      final index = await widget.backend.openHistoryIndex();
      if (mounted) setState(() => _bind(index));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update the index. Check available storage.',
        );
      }
    }
    if (mounted) setState(() => _busy = false);
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
            'Off by default. Turning it off removes indexed message text. Your chat history stays intact.',
          ),
          value: index?.enabled ?? false,
          onChanged: _busy ? null : (v) => _change(v),
        ),
        const Text(
          'Media indexing stores event IDs and media types. It does not download image, video or audio files.',
        ),
        if (index != null) ...[
          Text(
            '${index.entries} indexed events · ${(index.capacityRatio * 100).clamp(0, 100).toStringAsFixed(0)}% of cache budget used',
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
            'The search cache has reached 80% of its ${index.limitMiB} MiB budget. '
            'SeND will prune search context from the oldest messages onward as space is needed. '
            'Your messages and media on the homeserver will not be deleted.',
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
