import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attentio_desktop/providers/devices_providers.dart';
import 'package:attentio_desktop/ui/pages/overview_page.dart';
import 'package:attentio_desktop/ui/widgets/app_shell.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with the given Riverpod
/// overrides so widget tests can exercise the UI without hitting the real
/// Rust bridge.
Widget _harness({required Widget child, List<Object> overrides = const []}) {
  return ProviderScope(
    overrides: overrides.cast(),
    // Wrap in a Scaffold so widgets that need a Material/ScaffoldMessenger
    // ancestor (e.g. the Bluetooth FilterChip) build as they do in-app, where
    // OverviewPage always lives inside AppShell's Scaffold.
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('OverviewPage', () {
    testWidgets('shows empty-state text when no devices are returned', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const []),
            ),
          ],
          child: const OverviewPage(),
        ),
      );

      await tester.pump();

      expect(
        find.text('No devices detected. Ensure your device(s) are connected.'),
        findsOneWidget,
      );
    });

    testWidgets('renders a card per returned device', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const [
                DeviceInfo(
                  serial: 'SN-ABC',
                  mode: 'Normal',
                  name: 'Desk Light',
                  transport: 'USB',
                ),
                DeviceInfo(
                  serial: 'SN-DEF',
                  mode: 'Normal',
                  name: 'Monitor Light',
                  transport: 'USB',
                ),
              ]),
            ),
          ],
          child: const OverviewPage(),
        ),
      );
      await tester.pump();

      expect(find.text('Desk Light'), findsOneWidget);
      expect(find.text('Monitor Light'), findsOneWidget);
    });

    testWidgets('shows transport indicators, Discover button and BLE toggle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const [
                DeviceInfo(
                  serial: 'SN-USB',
                  mode: 'Normal',
                  name: 'Desk Light',
                  transport: 'USB',
                ),
                DeviceInfo(
                  serial: 'AA:BB:CC:DD:EE:FF',
                  mode: 'Normal',
                  name: 'BLE Light',
                  transport: 'BLE',
                  paired: true,
                ),
              ]),
            ),
          ],
          child: const OverviewPage(),
        ),
      );
      await tester.pump();

      expect(find.text('USB'), findsOneWidget);
      expect(find.text('BLE · Paired'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
    });

    testWidgets('settings button is visible', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const []),
            ),
          ],
          child: const OverviewPage(),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('Settings'), findsOneWidget);
    });
  });

  group('AppShell', () {
    testWidgets('displays the overview page', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            devicesStreamProvider.overrideWith(
              (ref) => Stream<List<DeviceInfo>>.value(const []),
            ),
          ],
          child: const AppShell(),
        ),
      );
      await tester.pump();

      expect(find.byType(OverviewPage), findsOneWidget);
    });
  });
}
