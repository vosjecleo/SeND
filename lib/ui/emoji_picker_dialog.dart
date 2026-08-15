import 'package:flutter/material.dart';

import '../services/emoji_repository.dart';

class EmojiPickerDialog extends StatefulWidget {
  const EmojiPickerDialog({super.key});

  @override
  State<EmojiPickerDialog> createState() => _EmojiPickerDialogState();
}

class _EmojiPickerDialogState extends State<EmojiPickerDialog> {
  final _query = TextEditingController();
  List<EmojiEntry> _results = const [];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search();
    _query.addListener(_search);
  }

  Future<void> _search() async {
    final generation = ++_generation;
    final results = await EmojiRepository.instance.search(
      _query.text,
      limit: 160,
    );
    if (mounted && generation == _generation) {
      setState(() => _results = results);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Emoji'),
    content: SizedBox(
      width: 540,
      height: 460,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search names and aliases',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 54,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final entry = _results[index];
                return Tooltip(
                  message: entry.name,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(entry.emoji),
                    child: Center(
                      child: Text(
                        entry.emoji,
                        style: const TextStyle(fontSize: 25),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
