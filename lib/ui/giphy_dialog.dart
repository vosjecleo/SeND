import 'package:flutter/material.dart';

import '../services/giphy_service.dart';

class GiphyDialog extends StatefulWidget {
  const GiphyDialog({required this.service, super.key});

  final GiphyService service;

  @override
  State<GiphyDialog> createState() => _GiphyDialogState();
}

class _GiphyDialogState extends State<GiphyDialog> {
  final _query = TextEditingController();
  List<GifSearchResult> _results = const [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final query = _query.text.trim();
    if (query.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.service.search(query);
      if (mounted) setState(() => _results = results);
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sticker / GIF'),
    content: SizedBox(
      width: 620,
      height: 500,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search Giphy',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _loading ? null : _search,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: _loading && _results.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final gif = _results[index];
                      return Tooltip(
                        message: gif.title,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(gif),
                          child: Image.network(
                            gif.previewUrl.toString(),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: Color(0xff292a30)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Powered by GIPHY',
              style: TextStyle(fontSize: 10, color: Color(0xff989aa5)),
            ),
          ),
        ],
      ),
    ),
  );
}
