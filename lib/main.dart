import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:attentio_desktop/app.dart';
import 'package:attentio_desktop/services/tray_service.dart';
import 'package:attentio_desktop/src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();

  // Desktop-only: initialise window & tray integration so the minimize-to-tray
  // setting can take effect.
  if (!Platform.isAndroid && !Platform.isIOS) {
    try {
      await windowManager.ensureInitialized();
      // Enforce a minimum window size so the UI never collapses below a
      // tested, usable footprint. 360×480 is a phone-portrait baseline:
      // below 360 px wide the AppBar title and first card start to clip.
      await windowManager.setMinimumSize(const Size(360, 480));
      await TrayService.instance.init();
    } catch (_) {
      // Running in a headless test environment — fall back gracefully.
    }
  }

  runApp(const ProviderScope(child: AttentioApp()));
}
