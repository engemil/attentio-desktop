import 'package:flutter/material.dart';

import 'package:attentio_desktop/features/devices/devices_page.dart';
import 'package:attentio_desktop/features/overview/overview_page.dart';
import 'package:attentio_desktop/features/settings/settings_page.dart';
import 'package:attentio_desktop/utils/responsive.dart';

/// Top-level navigation destinations shown in the sidebar.
enum AppSection { overview, devices, settings }

/// Static metadata for a single navigation destination.
class _NavDestination {
  const _NavDestination({
    required this.section,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final AppSection section;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavDestination> _kDestinations = [
  _NavDestination(
    section: AppSection.overview,
    label: 'Overview',
    icon: Icons.home,
    selectedIcon: Icons.home,
  ),
  _NavDestination(
    section: AppSection.devices,
    label: 'Devices',
    icon: Icons.devices,
    selectedIcon: Icons.devices,
  ),
  _NavDestination(
    section: AppSection.settings,
    label: 'Settings',
    icon: Icons.settings,
    selectedIcon: Icons.settings,
  ),
];

/// Root scaffold containing the sidebar and the currently-selected page.
///
/// The sidebar adapts to the viewport width: a `Drawer` at compact widths,
/// an icon rail at medium, and the full extended sidebar at large widths.
/// At extended widths the user can manually collapse it to a rail.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _selected = AppSection.overview;

  /// User's manual collapse choice. Only meaningful at `>= kMediumWidth`,
  /// where it switches the persistent sidebar between extended and rail.
  /// Below `kMediumWidth` the sidebar is forced to rail or drawer regardless.
  /// Session-only (not persisted across launches).
  bool _userCollapsed = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

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

  void _select(AppSection s, {bool fromDrawer = false}) {
    setState(() => _selected = s);
    if (fromDrawer) {
      // Close the drawer after selection.
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = resolveNavMode(
          constraints.maxWidth,
          userCollapsed: _userCollapsed,
        );

        Widget? leading;
        switch (mode) {
          case NavMode.drawer:
            leading = IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Open navigation',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            );
            break;
          case NavMode.extended:
            leading = IconButton(
              icon: const Icon(Icons.menu_open),
              tooltip: 'Collapse sidebar',
              onPressed: () => setState(() => _userCollapsed = true),
            );
            break;
          case NavMode.rail:
            // At the medium breakpoint, allow re-expanding via the AppBar.
            // (At < medium we wouldn't fit the extended sidebar.)
            if (constraints.maxWidth >= kMediumWidth) {
              leading = IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Expand sidebar',
                onPressed: () => setState(() => _userCollapsed = false),
              );
            }
            break;
        }

        final scaffold = Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            leading: leading,
            title: Text(_titleFor(_selected)),
          ),
          drawer: mode == NavMode.drawer
              ? Drawer(
                  child: SafeArea(
                    child: _ExtendedNavList(
                      selected: _selected,
                      onSelect: (s) => _select(s, fromDrawer: true),
                    ),
                  ),
                )
              : null,
          body: Row(
            children: [
              if (mode == NavMode.extended)
                _ExtendedSidebar(
                  selected: _selected,
                  onSelect: (s) => _select(s),
                ),
              if (mode == NavMode.rail)
                _NavRail(
                  selected: _selected,
                  onSelect: (s) => _select(s),
                ),
              if (mode != NavMode.drawer) const VerticalDivider(width: 1),
              Expanded(child: _buildPage()),
            ],
          ),
        );

        return scaffold;
      },
    );
  }
}

/// Full-width sidebar with icon + label list tiles.
class _ExtendedSidebar extends StatelessWidget {
  const _ExtendedSidebar({required this.selected, required this.onSelect});

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kExtendedSidebarWidth,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: _ExtendedNavList(selected: selected, onSelect: onSelect),
    );
  }
}

/// The list-of-tiles content shared by [_ExtendedSidebar] and the `Drawer`.
class _ExtendedNavList extends StatelessWidget {
  const _ExtendedNavList({required this.selected, required this.onSelect});

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final d in _kDestinations)
          ListTile(
            leading: Icon(d.section == selected ? d.selectedIcon : d.icon),
            title: Text(d.label),
            selected: d.section == selected,
            onTap: () => onSelect(d.section),
          ),
      ],
    );
  }
}

/// Icon-only navigation rail with short labels under each icon.
class _NavRail extends StatelessWidget {
  const _NavRail({required this.selected, required this.onSelect});

  final AppSection selected;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        _kDestinations.indexWhere((d) => d.section == selected);
    return NavigationRail(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (i) => onSelect(_kDestinations[i].section),
      labelType: NavigationRailLabelType.all,
      destinations: [
        for (final d in _kDestinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
    );
  }
}
