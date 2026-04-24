import 'package:flutter/material.dart';

import 'package:attentio_desktop/features/devices/devices_page.dart';
import 'package:attentio_desktop/features/overview/overview_page.dart';
import 'package:attentio_desktop/features/settings/settings_page.dart';

/// Top-level navigation destinations shown in the sidebar.
enum AppSection { overview, devices, settings }

/// Root scaffold containing the sidebar and the currently-selected page.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _selected = AppSection.overview;

  Widget _buildPage() {
    switch (_selected) {
      case AppSection.overview:
        return const OverviewPage();
      case AppSection.devices:
        return const DevicesPage();
      case AppSection.settings:
        return const SettingsPage();
    }
  }

  String _titleFor(AppSection section) {
    switch (section) {
      case AppSection.overview:
        return 'Overview';
      case AppSection.devices:
        return 'Devices';
      case AppSection.settings:
        return 'Settings';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titleFor(_selected))),
      body: Row(
        children: [
          _Sidebar(
            selected: _selected,
            onSelect: (s) => setState(() => _selected = s),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPage()),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Overview'),
            selected: selected == AppSection.overview,
            onTap: () => onSelect(AppSection.overview),
          ),
          ListTile(
            leading: const Icon(Icons.devices_other),
            title: const Text('Devices'),
            selected: selected == AppSection.devices,
            onTap: () => onSelect(AppSection.devices),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            selected: selected == AppSection.settings,
            onTap: () => onSelect(AppSection.settings),
          ),
        ],
      ),
    );
  }
}
