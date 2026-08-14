import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backend/chat_backend.dart';
import 'models/chat_models.dart';
import 'ui/chat_shell.dart';
import 'ui/login_screen.dart';

class DeltiecordApp extends StatelessWidget {
  const DeltiecordApp({required this.backend, super.key});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Deltiecord',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xff6975d9),
        scaffoldBackgroundColor: const Color(0xff25262c),
        useMaterial3: true,
      ),
      home: ListenableBuilder(
        listenable: backend,
        builder: (context, _) => switch (backend.status) {
          SessionStatus.starting => const _StartupScreen(),
          SessionStatus.failed => _StartupFailure(
            message: backend.error ?? 'Deltiecord could not start.',
            onRetry: backend.initialize,
          ),
          SessionStatus.signedIn => ChatShell(backend: backend),
          SessionStatus.signedOut ||
          SessionStatus.signingIn => LoginScreen(backend: backend),
        },
      ),
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Opening Deltiecord…'),
        ],
      ),
    ),
  );
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    ),
  );
}
