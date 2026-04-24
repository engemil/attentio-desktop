import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported application languages. Only English is supported for now; this
/// enum is kept as an extension point for future localisation work.
enum AppLanguage { english }

/// All user-configurable application preferences persisted between runs.
@immutable
class AppSettings {
  /// Active theme mode — system, light, or dark.
  final ThemeMode themeMode;

  /// Seed colour used to derive the Material 3 [ColorScheme].
  final Color accentColor;

  /// Selected UI language.
  final AppLanguage language;

  /// When true, closing the main window hides it to the system tray instead
  /// of quitting the application.
  final bool minimizeToTrayOnClose;

  /// When true, the application is launched automatically when the user logs
  /// into their desktop session.
  final bool autostartOnLogin;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.accentColor = const Color(0xFF2196F3), // Colors.blue
    this.language = AppLanguage.english,
    this.minimizeToTrayOnClose = false,
    this.autostartOnLogin = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    Color? accentColor,
    AppLanguage? language,
    bool? minimizeToTrayOnClose,
    bool? autostartOnLogin,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      language: language ?? this.language,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      autostartOnLogin: autostartOnLogin ?? this.autostartOnLogin,
    );
  }
}

const _kThemeModeKey = 'settings.themeMode';
const _kAccentColorKey = 'settings.accentColor';
const _kLanguageKey = 'settings.language';
const _kMinimizeToTrayKey = 'settings.minimizeToTrayOnClose';
const _kAutostartKey = 'settings.autostartOnLogin';

/// Riverpod notifier that loads settings from [SharedPreferences] at startup
/// and persists any user-initiated change.
class AppSettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // Kick off async load; return a sensible default in the meantime.
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      themeMode: _decodeThemeMode(prefs.getString(_kThemeModeKey)),
      accentColor: _decodeColor(prefs.getInt(_kAccentColorKey)),
      language: _decodeLanguage(prefs.getString(_kLanguageKey)),
      minimizeToTrayOnClose: prefs.getBool(_kMinimizeToTrayKey) ?? false,
      autostartOnLogin: prefs.getBool(_kAutostartKey) ?? false,
    );
    await _applyAutostart(state.autostartOnLogin);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setAccentColor(Color color) async {
    state = state.copyWith(accentColor: color);
    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use
    await prefs.setInt(_kAccentColorKey, color.value);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = state.copyWith(language: language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguageKey, language.name);
  }

  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    state = state.copyWith(minimizeToTrayOnClose: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMinimizeToTrayKey, enabled);
  }

  Future<void> setAutostartOnLogin(bool enabled) async {
    state = state.copyWith(autostartOnLogin: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutostartKey, enabled);
    await _applyAutostart(enabled);
  }

  Future<void> _applyAutostart(bool enabled) async {
    // `launch_at_startup` must be configured with the executable path.
    try {
      final info = await PackageInfo.fromPlatform();
      LaunchAtStartup.instance.setup(
        appName: info.appName.isEmpty ? 'attentio_desktop' : info.appName,
        appPath: Platform.resolvedExecutable,
      );
      if (enabled) {
        await LaunchAtStartup.instance.enable();
      } else {
        await LaunchAtStartup.instance.disable();
      }
    } catch (_) {
      // Autostart isn't critical — ignore platform-specific failures (e.g.
      // running as a snap/flatpak where autostart hooks differ).
    }
  }
}

ThemeMode _decodeThemeMode(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

Color _decodeColor(int? raw) =>
    raw == null ? const Color(0xFF2196F3) : Color(raw);

AppLanguage _decodeLanguage(String? raw) {
  switch (raw) {
    case 'english':
    default:
      return AppLanguage.english;
  }
}

/// Exposes the current [AppSettings] and a notifier for mutating them.
final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
