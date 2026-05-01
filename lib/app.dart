import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/features/settings/settings_provider.dart';
import 'package:attentio_desktop/features/shell/app_shell.dart';
import 'package:attentio_desktop/services/tray_service.dart';

/// Top-level [MaterialApp] wrapper.
///
/// Watches [appSettingsProvider] so theme, colour scheme, and window/tray
/// behaviour update live when the user changes them from the Settings page.
class AttentioApp extends ConsumerWidget {
  const AttentioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    // Keep the tray service in sync with the user's minimize-to-tray choice.
    // Apply the current value on every rebuild (idempotent) and also listen
    // for changes for immediate reaction without waiting for the next rebuild.
    TrayService.instance.setMinimizeToTray(settings.minimizeToTrayOnClose);
    ref.listen<bool>(
      appSettingsProvider.select((s) => s.minimizeToTrayOnClose),
      (_, next) => TrayService.instance.setMinimizeToTray(next),
    );

    final lightScheme =
        ColorScheme.fromSeed(seedColor: settings.accentColor);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: settings.accentColor,
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Attentio Desktop',
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: lightScheme.primary.withValues(alpha: 0.08),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        splashFactory: NoSplash.splashFactory,
        highlightColor: darkScheme.primary.withValues(alpha: 0.08),
      ),
      home: const AppShell(),
    );
  }
}
