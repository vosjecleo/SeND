import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'backend/chat_backend.dart';
import 'models/chat_models.dart';
import 'services/desktop_window_service.dart';
import 'ui/chat_shell.dart';
import 'ui/deltiecord_theme.dart';
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
        final palette = DeltiecordPalette.forMode(preferences.themeMode);
        final brightness = preferences.themeMode == DeltiecordThemeMode.light
            ? Brightness.light
            : Brightness.dark;
        final colorScheme = ColorScheme.fromSeed(
          seedColor: Color(preferences.accentColor),
          brightness: brightness,
          contrastLevel: contrast ? 1 : 0,
        ).copyWith(surface: palette.surface, onSurface: palette.text);
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
            brightness: brightness,
            colorScheme: colorScheme,
            iconTheme: IconThemeData(color: colorScheme.primary),
            scaffoldBackgroundColor: palette.background,
            canvasColor: palette.surface,
            cardColor: palette.elevated,
            dividerColor: palette.divider,
            extensions: [palette],
            fontFamily: preferences.fontFamily == 'System'
                ? null
                : preferences.fontFamily,
            visualDensity: VisualDensity(
              horizontal: -2 * preferences.compactness,
              vertical: -2 * preferences.compactness,
            ),
            pageTransitionsTheme: preferences.reducedMotion
                ? const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.linux: _NoMotionPageTransitionsBuilder(),
                      TargetPlatform.android: _NoMotionPageTransitionsBuilder(),
                    },
                  )
                : const PageTransitionsTheme(),
            useMaterial3: true,
            dialogTheme: DialogThemeData(
              backgroundColor: palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(3)),
                side: BorderSide(color: palette.divider),
              ),
            ),
            appBarTheme: AppBarTheme(
              backgroundColor: palette.surface,
              foregroundColor: palette.text,
              surfaceTintColor: Colors.transparent,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: palette.input,
              border: OutlineInputBorder(
                borderSide: BorderSide(color: palette.divider),
                borderRadius: const BorderRadius.all(Radius.circular(3)),
              ),
            ),
            menuTheme: MenuThemeData(
              style: MenuStyle(
                backgroundColor: WidgetStatePropertyAll(palette.elevated),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(Radius.circular(2)),
                    side: BorderSide(color: palette.divider),
                  ),
                ),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 3),
                ),
              ),
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: palette.elevated,
              shape: RoundedRectangleBorder(
                borderRadius: const BorderRadius.all(Radius.circular(2)),
                side: BorderSide(color: palette.divider),
              ),
            ),
            tooltipTheme: TooltipThemeData(
              waitDuration: const Duration(milliseconds: 450),
              showDuration: const Duration(seconds: 4),
              decoration: BoxDecoration(
                color: palette.elevated,
                border: Border.fromBorderSide(
                  BorderSide(color: palette.divider),
                ),
              ),
              textStyle: TextStyle(color: palette.text, fontSize: 11),
            ),
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final interfaceScale = preferences.interfaceScale;
            final scaledMedia = media.copyWith(
              size: media.size / interfaceScale,
              textScaler: TextScaler.linear(preferences.fontScale),
              disableAnimations: preferences.reducedMotion,
              highContrast: preferences.highContrast,
            );
            final content = MediaQuery(data: scaledMedia, child: child!);
            if (interfaceScale == 1) return content;
            return ClipRect(
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: media.size.width / interfaceScale,
                  height: media.size.height / interfaceScale,
                  child: content,
                ),
              ),
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
