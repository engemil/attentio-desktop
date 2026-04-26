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

    testWidgets('compact width shows hamburger that opens a Drawer',
        (tester) async {
      // Phone-portrait baseline: below kCompactWidth (600).
      await tester.binding.setSurfaceSize(const Size(420, 720));
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

      // No persistent sidebar tiles visible at compact width.
      expect(find.widgetWithText(ListTile, 'Devices'), findsNothing);

      // The AppBar shows a hamburger.
      final hamburger = find.byTooltip('Open navigation');
      expect(hamburger, findsOneWidget);

      // Tapping it opens the drawer with the destination tiles.
      await tester.tap(hamburger);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Devices'), findsOneWidget);

      // Selecting a destination switches page and closes the drawer.
      await tester.tap(find.widgetWithText(ListTile, 'Devices'));
      await tester.pumpAndSettle();
      expect(find.byType(DevicesPage), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Devices'), findsNothing);
    });

    testWidgets('extended width allows collapse to rail and back',
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

      // Extended sidebar shows label tiles.
      expect(find.widgetWithText(ListTile, 'Devices'), findsOneWidget);

      // Collapse to rail.
      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();

      // Rail does not use ListTile; labels are still findable as Text.
      expect(find.widgetWithText(ListTile, 'Devices'), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);

      // Expand again.
      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Devices'), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });
}
