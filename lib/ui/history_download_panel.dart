import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';
import '../services/history_download.dart';
import '../services/history_index.dart';

class HistoryDownloadPanel extends StatefulWidget {
  const HistoryDownloadPanel({
    required this.backend,
    required this.index,
    required this.download,
    required this.increaseLimit,
    super.key,
  });
  final ChatBackend backend;
  final HistoryIndex index;
  final HistoryDownload download;
  final Future<bool> Function(int limit) increaseLimit;
  @override
  State<HistoryDownloadPanel> createState() => _HistoryDownloadPanelState();
}

class _HistoryDownloadPanelState extends State<HistoryDownloadPanel> {
  String _scope = 'all';
  bool _busy = false;
  String? _error;
  String get _effectiveScope =>
      _scope != 'all' &&
          (widget.backend.selectedRoom?.id != _scope ||
              !widget.backend.historyDownloadRooms.any(
                (r) => r.id == _scope && widget.index.scope.includes(r.kind),
              ))
      ? 'all'
      : _scope;

  Future<void> _start() async {
    final rooms = widget.backend.historyDownloadRooms
        .where((r) => widget.index.scope.includes(r.kind))
        .toList();
    final scope = _effectiveScope;
    final selected = scope == 'all'
        ? rooms.map((r) => r.id).toList()
        : rooms.where((r) => r.id == scope).map((r) => r.id).toList();
    if (selected.isEmpty) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Download message history?'),
        content: Text(
          'Fetch all accessible message events for ${selected.length} ${selected.length == 1 ? 'chat' : 'chats'}. '
          'Photos, videos and other attachment files will not be downloaded. '
          '${widget.index.encryptedAtRest ? '' : 'The search database stores decrypted text without separate encryption. '}'
          'Large histories can use a lot of data; use Wi-Fi if needed. '
          'The download pauses at your search-cache limit. Progress stays on this device, and no messages are marked read. '
          'On mobile, leaving SeND pauses the download. You can resume in Storage settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Download history'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() => widget.download.start(selected));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        _error =
            'Could not start the history download. Check storage and try again.';
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _increase() async {
    final next = [
      25,
      50,
      100,
      250,
      500,
      1024,
      2048,
    ].where((n) => n > widget.index.limitMiB).firstOrNull;
    if (next == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Increase the search cache?'),
        content: Text(
          'Raise the limit from ${widget.index.limitMiB} MiB to $next MiB and resume the saved download.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Use $next MiB'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    await _run(() async {
      if (await widget.increaseLimit(next)) await widget.download.resume();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.download,
    builder: (context, _) {
      final job = widget.download;
      final notice =
          job.status == HistoryDownloadStatus.full &&
              widget.index.limitMiB >= 2048
          ? 'The 2048 MiB cache limit is reached. Keep the partial index, or start a smaller download.'
          : job.message;
      final rooms = widget.backend.historyDownloadRooms
          .where((r) => widget.index.scope.includes(r.kind))
          .toList();
      final selected = widget.backend.selectedRoom;
      final current = selected == null
          ? null
          : rooms.where((r) => r.id == selected.id).firstOrNull;
      final scope = _effectiveScope;
      final room = rooms.where((r) => r.id == job.currentRoom).firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 28),
          Text(
            'Download history for search',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Download message text and media references without fetching the attachment files. Search results stay available locally. Missing encryption keys can leave gaps.',
          ),
          if (!widget.index.encryptedAtRest)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'The local search database stores decrypted text without separate encryption.',
              ),
            ),
          if (!widget.index.enabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Enable local text indexing above to download history.',
              ),
            ),
          if (!job.running)
            DropdownButtonFormField<String>(
              key: ValueKey('history-download-scope-$scope-${current?.id}'),
              initialValue: scope,
              decoration: const InputDecoration(labelText: 'Chats to download'),
              isExpanded: true,
              items: [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('All chats in selected scope (${rooms.length})'),
                ),
                if (current != null)
                  DropdownMenuItem(
                    value: current.id,
                    child: Text(
                      'This chat: ${current.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) {
                      if (value != null) setState(() => _scope = value);
                    },
            ),
          if (job.totalRooms > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${job.completedRooms}/${job.totalRooms} chats complete · ${job.checked} events processed',
            ),
            if (job.running && room != null)
              Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (job.unavailable > 0)
              Text(
                '${job.unavailable} encrypted events could not be decrypted.',
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(notice),
              ),
            if (job.running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (job.running)
                OutlinedButton(
                  onPressed: job.pause,
                  child: const Text('Pause download'),
                )
              else ...[
                if (job.hasCheckpoint)
                  FilledButton(
                    onPressed: _busy || !widget.index.enabled
                        ? null
                        : () => _run(job.resume),
                    child: const Text('Resume download'),
                  ),
                if (job.status == HistoryDownloadStatus.full &&
                    widget.index.limitMiB < 2048)
                  OutlinedButton(
                    onPressed: _busy ? null : _increase,
                    child: const Text('Increase limit and resume'),
                  ),
                OutlinedButton(
                  onPressed: _busy || !widget.index.enabled || rooms.isEmpty
                      ? null
                      : _start,
                  child: Text(
                    job.hasCheckpoint ? 'New download' : 'Download history',
                  ),
                ),
              ],
            ],
          ),
          if (_error != null) Text(_error!),
        ],
      );
    },
  );
}
