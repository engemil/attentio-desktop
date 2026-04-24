import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attentio_desktop/features/devices/devices_page.dart';
import 'package:attentio_desktop/features/devices/devices_providers.dart';
import 'package:attentio_desktop/features/overview/overview_page.dart';
import 'package:attentio_desktop/features/settings/settings_page.dart';
import 'package:attentio_desktop/features/shell/app_shell.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with the given Riverpod
/// overrides so widget tests can exercise the UI without hitting the real
/// Rust bridge.
Widget _harness({
  required Widget child,
  List<Object> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(home: child),
  );
}void main() {
  group('DevicesPage', () {
    testWidgets('shows empty-state text when no devices are returned',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
                (ref) => Stream<List<DeviceInfo>>.value(const [])),
          ],
          child: const DevicesPage(),
        ),
      );

      await tester.pump();

      expect(
        find.text('No devices found. Ensure your AL-1 is connected.'),
        findsOneWidget,
      );
    });

    testWidgets('renders a card per returned device', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const [
                DeviceInfo(serial: 'SN-ABC', mode: 'Normal'),
                DeviceInfo(serial: 'SN-DEF', mode: 'Normal'),
              ]),
            ),
          ],
          child: const DevicesPage(),
        ),
      );
      await tester.pump();

      expect(find.text('Serial: SN-ABC'), findsOneWidget);
      expect(find.text('Serial: SN-DEF'), findsOneWidget);
    });
  });

  group('AppShell', () {
    testWidgets('sidebar switches between Overview, Devices, and Settings',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
                (ref) => Stream<List<DeviceInfo>>.value(const [])),
          ],
          child: const AppShell(),
        ),
      );
      await tester.pump();

      // Defaults to Overview.
      expect(find.byType(OverviewPage), findsOneWidget);
      expect(find.byType(DevicesPage), findsNothing);
      expect(find.byType(SettingsPage), findsNothing);

      // Tap the Devices sidebar tile.
      await tester.tap(find.widgetWithText(ListTile, 'Devices'));
      await tester.pumpAndSettle();
      expect(find.byType(DevicesPage), findsOneWidget);
      expect(find.byType(OverviewPage), findsNothing);

      // Tap the Settings sidebar tile.
      await tester.tap(find.widgetWithText(ListTile, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(DevicesPage), findsNothing);
    });
  });
}
