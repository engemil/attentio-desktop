import 'package:flutter/material.dart';

import 'package:attentio_desktop/ui/pages/overview_page.dart';

/// Root scaffold. The overview page is the sole top-level view; settings are
/// accessible via an icon button on the overview header.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: OverviewPage(),
    );
  }
}
