// Isolated physical-device fixture. No accounts, Matrix client or private data.
import 'package:flutter/material.dart';
import 'package:deltiecord/ui/archive_navigation.dart';
import 'package:deltiecord/ui/threshold_feedback.dart';
import '../test/support/fake_backend.dart';

void main() =>
    runApp(MaterialApp(theme: ThemeData.dark(), home: const _Probe()));

class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  final backend = FakeBackend();
  int replies = 0;
  @override
  void dispose() {
    backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SeND gesture test')),
    body: SafeArea(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Pull down the list for Archive. Swipe the last row to reply.',
            ),
          ),
          Expanded(
            child: ArchivePullList(
              backend: backend,
              itemCount: 20,
              itemBuilder: (_, index) => SizedBox(
                height: 56,
                child: ListTile(title: Text('Test chat $index')),
              ),
            ),
          ),
          const Divider(),
          SwipeToReply(
            messageId: 'probe',
            onReply: () => setState(() => replies++),
            child: SizedBox(
              height: 100,
              child: Center(child: Text('Swipe to reply ($replies)')),
            ),
          ),
        ],
      ),
    ),
  );
}
