import 'package:flutter/material.dart';
import '../backend/chat_backend.dart';

Future<void> showCreateServerDialog(
  BuildContext context,
  ChatBackend backend,
) => showDialog<void>(
  context: context,
  builder: (_) => _CreateServerDialog(backend),
);

class _CreateServerDialog extends StatefulWidget {
  const _CreateServerDialog(this.backend);
  final ChatBackend backend;
  @override
  State<_CreateServerDialog> createState() => _CreateServerDialogState();
}

class _CreateServerDialogState extends State<_CreateServerDialog> {
  final _name = TextEditingController(), _topic = TextEditingController();
  String _access = 'invite';
  bool _encrypted = true, _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy || _name.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.backend.createSpace(
        name: _name.text.trim(),
        topic: _topic.text.trim(),
        encrypted: _encrypted,
        channelAccess: _access,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Could not create the server. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Create server'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              enabled: !_busy,
              decoration: const InputDecoration(labelText: 'Server name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topic,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _access,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Default access for new channels',
              ),
              items: const [
                DropdownMenuItem(value: 'invite', child: Text('Invite only')),
                DropdownMenuItem(
                  value: 'restricted',
                  child: Text('Members of this server'),
                ),
                DropdownMenuItem(value: 'public', child: Text('Anyone')),
              ],
              onChanged: _busy ? null : (v) => setState(() => _access = v!),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Encrypt new channels'),
              subtitle: const Text(
                'Without encryption, homeserver operators can read messages. Encryption cannot be turned off in existing channels.',
              ),
              value: _encrypted,
              onChanged: _busy ? null : (v) => setState(() => _encrypted = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || _name.text.trim().isEmpty ? null : _create,
          child: Text(_busy ? 'Creating…' : 'Create'),
        ),
      ],
    ),
  );
}
