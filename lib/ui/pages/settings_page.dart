import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:attentio_desktop/providers/settings_provider.dart';

/// Breakpoint (content-area width) at which wide trailing controls switch from
/// an inline trailing position to a stacked layout below the label.
const double _kSettingsResponsiveBreakpoint = 580;

/// Maximum content width for the settings page; prevents overly stretched
/// rows on wide windows.
const double _kSettingsMaxContentWidth = 720;

/// Full settings page — Appearance, Application behaviour, and About.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kSettingsMaxContentWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(
                title: 'Appearance',
                children: [
                  _ThemeModeTile(
                    current: settings.themeMode,
                    onChanged: notifier.setThemeMode,
                  ),
                  const Divider(height: 1),
                  _AccentColorTile(
                    current: settings.accentColor,
                    onChanged: notifier.setAccentColor,
                  ),
                  const Divider(height: 1),
                  _LanguageTile(
                    current: settings.language,
                    onChanged: notifier.setLanguage,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(
                title: 'Application',
                children: [
                  SwitchListTile(
                    title: const Text('Minimize to system tray on close'),
                    subtitle: const Text(
                      'Closing the window hides it to the system tray '
                      'instead of quitting the application.',
                    ),
                    secondary: const Icon(Icons.minimize),
                    value: settings.minimizeToTrayOnClose,
                    onChanged: notifier.setMinimizeToTrayOnClose,
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Autostart on login'),
                    subtitle: const Text(
                      'Launch Attentio Desktop automatically when you log '
                      'in.',
                    ),
                    secondary: const Icon(Icons.power_settings_new),
                    value: settings.autostartOnLogin,
                    onChanged: notifier.setAutostartOnLogin,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _Section(title: 'About', children: const [_AboutTile()]),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A settings row that renders its [control] to the right of the label on
/// wide windows, but stacks the control below the label/subtitle on narrow
/// windows. Works around the tight width constraint of [ListTile.trailing].
class _ResponsiveSettingTile extends StatelessWidget {
  const _ResponsiveSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kSettingsResponsiveBreakpoint;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(context).iconTheme.color),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: control,
                  ),
                ),
              ],
            ),
          );
        }
        // Narrow: stack the control under the label.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: Theme.of(context).iconTheme.color),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: control,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingTile(
      icon: Icons.brightness_6,
      title: 'Theme',
      subtitle: 'Choose between light, dark, or follow system.',
      control: SegmentedButton<ThemeMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            label: Text('System', softWrap: false),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Light', softWrap: false),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dark', softWrap: false),
          ),
        ],
        selected: {current},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class _AccentColorTile extends StatelessWidget {
  const _AccentColorTile({required this.current, required this.onChanged});

  final Color current;
  final ValueChanged<Color> onChanged;

  static const _palette = <Color>[
    Color(0xFF2196F3), // blue
    Color(0xFF3F51B5), // indigo
    Color(0xFF9C27B0), // purple
    Color(0xFFE91E63), // pink
    Color(0xFFF44336), // red
    Color(0xFFFF9800), // orange
    Color(0xFF4CAF50), // green
    Color(0xFF009688), // teal
    Color(0xFF607D8B), // blue grey
  ];

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingTile(
      icon: Icons.color_lens,
      title: 'Accent colour',
      subtitle: 'Seed colour used to derive the application colour scheme.',
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in _palette)
            _ColorDot(
              color: c,
              // ignore: deprecated_member_use
              selected: c.value == current.value,
              onTap: () => onChanged(c),
            ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.current, required this.onChanged});

  final AppLanguage current;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveSettingTile(
      icon: Icons.language,
      title: 'Language',
      subtitle: 'Only English is available right now.',
      control: DropdownButton<AppLanguage>(
        value: current,
        onChanged: (v) => v == null ? null : onChanged(v),
        items: const [
          DropdownMenuItem(value: AppLanguage.english, child: Text('English')),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null
            ? '…'
            : '${info.version}+${info.buildNumber}';
        final appName = info?.appName ?? 'Attentio Desktop';
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.lightbulb),
              title: Text(appName),
              subtitle: const Text('Desktop GUI for AttentioLight-1 devices.'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
              trailing: Text(version),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Source code'),
              subtitle: const Text('github.com/engemil/attentio-desktop'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                final uri = Uri.parse(
                  'https://github.com/engemil/attentio-desktop',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('License'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _AppLicensePage(
                      appName: appName,
                      version: version,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

/// A simple page showing only the application's own license text.
class _AppLicensePage extends StatelessWidget {
  const _AppLicensePage({
    required this.appName,
    required this.version,
  });

  final String appName;
  final String version;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$appName License')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('LICENSE'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load license.'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              snapshot.data ?? '',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    height: 1.5,
                  ),
            ),
          );
        },
      ),
    );
  }
}
