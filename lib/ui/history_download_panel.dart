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
          'Download messages from ${selected.length} ${selected.length == 1 ? 'chat' : 'chats'} for search? Attachments won\'t be downloaded. ${widget.index.encryptedAtRest ? '' : 'Message text will be stored unencrypted on this device. '}On mobile, keep SeND open; resume paused downloads in Storage.',
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
          'Increase storage from ${widget.index.limitMiB} MiB to $next MiB and resume?',
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
      if (await widget.increaseLimit(next)) {
        if (widget.download.hasCheckpoint) {
          await widget.download.resume();
        } else {
          await widget.download.retryFailed();
        }
      }
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
            'Download messages for offline search, without attachments.',
          ),
          if (!widget.index.encryptedAtRest)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Message text is stored unencrypted on this device.'),
            ),
          if (!widget.index.enabled)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Enable local text indexing above to download history.',
              ),
            ),
          if (!job.running && !job.retrying)
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
              '${job.completedRooms}/${job.totalRooms} chats · ${job.checked} events processed',
            ),
            if (job.running && room != null)
              Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (job.unavailable > 0)
              Text('Encrypted events missing from search: ${job.unavailable}.'),

            if (job.failures.isNotEmpty)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _FailedEventsDialog(
                    backend: widget.backend,
                    download: job,
                  ),
                ),
                child: Text('Review failed events (${job.failures.length})'),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(notice),
              ),
            if (job.running || job.retrying)
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
              if (job.running || job.retrying)
                OutlinedButton(
                  onPressed: job.pause,
                  child: Text(job.retrying ? 'Pause retry' : 'Pause download'),
                )
              else ...[
                if (job.failures.isNotEmpty)
                  OutlinedButton(
                    onPressed: _busy || !widget.index.enabled
                        ? null
                        : () => _run(job.retryFailed),
                    child: const Text('Retry decryption'),
                  ),
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

class _FailedEventsDialog extends StatefulWidget {
  const _FailedEventsDialog({required this.backend, required this.download});
  final ChatBackend backend;
  final HistoryDownload download;
  @override
  State<_FailedEventsDialog> createState() => _FailedEventsDialogState();
}

class _FailedEventsDialogState extends State<_FailedEventsDialog> {
  int _page = 0;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.download,
    builder: (context, _) {
      final events = widget.download.failures;
      final count = ((events.length + 19) ~/ 20).clamp(1, 500);
      final page = _page.clamp(0, count - 1);
      final rooms = {
        for (final room in widget.backend.historyDownloadRooms)
          room.id: room.name,
      };
      return AlertDialog(
        title: Text('Events missing from search (${events.length})'),
        content: SizedBox(
          width: 600,
          height: MediaQuery.sizeOf(context).height * .45,
          child: events.isEmpty
              ? const Text('No failed events remain.')
              : ListView(
                  children: [
                    for (final event in events.skip(page * 20).take(20))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(rooms[event.roomId] ?? event.roomId),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (event.senderId.isNotEmpty) Text(event.senderId),
                            if (event.timestamp > 0)
                              Text(
                                DateTime.fromMillisecondsSinceEpoch(
                                  event.timestamp,
                                ).toLocal().toString(),
                              ),
                            SelectableText(event.eventId),
                            const Text('Encrypted content unavailable.'),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          IconButton(
            tooltip: 'Previous failed events',
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page + 1}/$count'),
          IconButton(
            tooltip: 'Next failed events',
            onPressed: page + 1 < count
                ? () => setState(() => _page = page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}
