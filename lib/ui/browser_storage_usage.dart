import 'package:flutter/material.dart';
import '../services/browser_storage.dart';

class BrowserStorageUsage extends StatefulWidget {
  const BrowserStorageUsage({super.key});
  @override
  State<BrowserStorageUsage> createState() => _BrowserStorageUsageState();
}

class _BrowserStorageUsageState extends State<BrowserStorageUsage> {
  late Future<Map<String, Object?>> _info = browserStorageInfo();
  String _mib(num bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MiB';
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _info,
    builder: (context, snapshot) {
      final info = snapshot.data;
      if (snapshot.hasError) {
        return const Text('Browser storage usage is unavailable.');
      }
      if (info == null) return const LinearProgressIndicator();
      final usage = info['usage'] as num? ?? 0,
          quota = info['quota'] as num? ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Browser storage',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text('${_mib(usage)} used of ${_mib(quota)} estimated allowance'),
          LinearProgressIndicator(
            value: quota <= 0 ? 0 : (usage / quota).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: 8),
          Text(
            info['persistent'] == true
                ? 'Persistent storage granted'
                : 'The browser may evict this data when space is low.',
          ),
          if (info['persistent'] != true)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    setState(() => _info = browserStorageInfo(persist: true)),
                child: const Text('Request persistent storage'),
              ),
            ),
          const Text(
            'Local data unlocks automatically with a browser-held key. Clearing site data removes it. This does not protect against compromised site code or a copied browser profile.',
          ),
        ],
      );
    },
  );
}
