import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Manages the optional system-tray icon and cooperates with [WindowManager]
/// to implement "minimize to tray on close" behaviour.
///
/// The service is idempotent — calling [setMinimizeToTray] multiple times
/// simply reconciles the tray icon and the window's `preventClose` flag.
class TrayService with TrayListener, WindowListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  bool _initialized = false;
  bool _trayInstalled = false;
  bool _minimizeToTray = false;

  /// Install window and tray listeners. Must be called once from [main] after
  /// [WindowManager.ensureInitialized].
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  bool get _isSupported {
    if (kIsWeb) return false;
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  /// Enable or disable the minimize-to-tray behaviour. When enabled the
  /// window's close button hides the window and the tray icon is installed;
  /// when disabled the tray icon is removed and closing quits normally.
  Future<void> setMinimizeToTray(bool enabled) async {
    if (!_isSupported) return;
    _minimizeToTray = enabled;

    try {
      await windowManager.setPreventClose(enabled);
    } catch (_) {}

    if (enabled) {
      await _installTray();
    } else {
      await _removeTray();
    }
  }

  Future<void> _installTray() async {
    if (_trayInstalled) return;
    try {
      // Use a small built-in icon path; fall back to empty if unavailable.
      // Users can replace this with a packaged asset later.
      await trayManager.setIcon(
        Platform.isWindows
            ? 'windows/runner/resources/app_icon.ico'
            : 'linux/runner/resources/app_icon.png',
      );
    } catch (_) {
      // Icon file might not exist yet; carry on without a custom icon.
    }

    try {
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: 'Show Attentio Desktop'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: 'Quit'),
          ],
        ),
      );
      _trayInstalled = true;
    } catch (_) {}
  }

  Future<void> _removeTray() async {
    if (!_trayInstalled) return;
    try {
      await trayManager.destroy();
    } catch (_) {}
    _trayInstalled = false;
  }

  // --- WindowListener -----------------------------------------------------

  @override
  void onWindowClose() async {
    if (!_minimizeToTray) return;
    try {
      await windowManager.hide();
    } catch (_) {}
  }

  // --- TrayListener -------------------------------------------------------

  @override
  void onTrayIconMouseDown() {
    windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await windowManager.show();
        break;
      case 'quit':
        await windowManager.setPreventClose(false);
        await windowManager.close();
        break;
    }
  }
}
