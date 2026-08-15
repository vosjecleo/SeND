import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backend/chat_backend.dart';
import 'models/chat_models.dart';
import 'services/desktop_window_service.dart';
import 'ui/chat_shell.dart';
import 'ui/login_screen.dart';

class DeltiecordApp extends StatelessWidget {
  const DeltiecordApp({required this.backend, super.key});

  final ChatBackend backend;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: backend,
      builder: (context, _) {
        final preferences = backend.preferences;
        if (backend.status == SessionStatus.signedIn) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => DesktopWindowService.apply(preferences),
          );
        }
        final contrast = preferences.highContrast;
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
            colorScheme: ColorScheme.fromSeed(
              seedColor: Color(preferences.accentColor),
              brightness: Brightness.dark,
              contrastLevel: contrast ? 1 : 0,
            ),
            scaffoldBackgroundColor: const Color(0xff25262c),
            fontFamily: preferences.fontFamily == 'System'
                ? null
                : preferences.fontFamily,
            visualDensity: preferences.density == InterfaceDensity.compact
                ? VisualDensity.compact
                : VisualDensity.standard,
            pageTransitionsTheme: preferences.reducedMotion
                ? const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.linux: _NoMotionPageTransitionsBuilder(),
                      TargetPlatform.android: _NoMotionPageTransitionsBuilder(),
                    },
                  )
                : const PageTransitionsTheme(),
            useMaterial3: true,
            dialogTheme: const DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(3)),
                side: BorderSide(color: Color(0xff555762)),
              ),
            ),
            menuTheme: const MenuThemeData(
              style: MenuStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                    side: BorderSide(color: Color(0xff555762)),
                  ),
                ),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 3),
                ),
              ),
            ),
            popupMenuTheme: const PopupMenuThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(2)),
                side: BorderSide(color: Color(0xff555762)),
              ),
            ),
            tooltipTheme: const TooltipThemeData(
              waitDuration: Duration(milliseconds: 450),
              showDuration: Duration(seconds: 4),
              decoration: BoxDecoration(
                color: Color(0xff16171b),
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xff555762)),
                ),
              ),
              textStyle: TextStyle(color: Color(0xffdedfe5), fontSize: 11),
            ),
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(preferences.fontScale),
                disableAnimations: preferences.reducedMotion,
                highContrast: preferences.highContrast,
              ),
              child: child!,
            );
          },
          home: switch (backend.status) {
            SessionStatus.starting => const _StartupScreen(),
            SessionStatus.failed => _StartupFailure(
              message: backend.error ?? 'Deltiecord could not start.',
              onRetry: backend.initialize,
            ),
            SessionStatus.signedIn => ChatShell(backend: backend),
            SessionStatus.signedOut ||
            SessionStatus.signingIn => LoginScreen(backend: backend),
          },
        );
      },
    );
  }
}

class _NoMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoMotionPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
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
