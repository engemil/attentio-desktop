import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:attentio_desktop/app.dart';
import 'package:attentio_desktop/ui/pages/overview_page.dart';
import 'package:attentio_desktop/src/rust/frb_generated.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// End-to-end smoke test: boots the real Rust bridge, runs the real app and
/// asserts that the dashboard eventually renders either a populated device
/// list or the empty-state message (both are valid, since CI/dev machines
/// typically don't have a device attached).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => RustLib.init());

  testWidgets('App boots and shows the dashboard', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AttentioApp()));

    // Let the FutureProvider resolve (device discovery times out after 5 s).
    await tester.pump(const Duration(seconds: 6));

    expect(find.byType(OverviewPage), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);

    // Either a device card appears, or the empty-state label does.
    final hasDevice = find.text('AttentioLight-1').evaluate().isNotEmpty;
    final hasEmpty = find
        .text('No devices detected. Ensure your device(s) are connected.')
        .evaluate()
        .isNotEmpty;
    expect(
      hasDevice || hasEmpty,
      isTrue,
      reason: 'Dashboard must render either a device list or the empty state.',
    );
  });
}
