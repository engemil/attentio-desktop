import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:attentio_desktop/features/settings/settings_provider.dart';

/// Full settings page — Appearance, Application behaviour, and About.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
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
                'Closing the window hides it to the system tray instead of '
                'quitting the application.',
              ),
              secondary: const Icon(Icons.minimize),
              value: settings.minimizeToTrayOnClose,
              onChanged: notifier.setMinimizeToTrayOnClose,
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('Autostart on login'),
              subtitle: const Text(
                'Launch Attentio Desktop automatically when you log in.',
              ),
              secondary: const Icon(Icons.power_settings_new),
              value: settings.autostartOnLogin,
              onChanged: notifier.setAutostartOnLogin,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _Section(
          title: 'About',
          children: const [_AboutTile()],
        ),
      ],
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

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({required this.current, required this.onChanged});

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.brightness_6),
      title: const Text('Theme'),
      subtitle: const Text('Choose between light, dark, or follow system.'),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            label: Text('System'),
            icon: Icon(Icons.brightness_auto),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Light'),
            icon: Icon(Icons.light_mode),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dark'),
            icon: Icon(Icons.dark_mode),
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
    return ListTile(
      leading: const Icon(Icons.color_lens),
      title: const Text('Accent colour'),
      subtitle: const Text(
          'Seed colour used to derive the application colour scheme.'),
      trailing: SizedBox(
        width: 240,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: [
            for (final c in _palette)
              _ColorDot(
                color: c,
                selected: c.value == current.value,
                onTap: () => onChanged(c),
              ),
          ],
        ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
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
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.current, required this.onChanged});

  final AppLanguage current;
  final ValueChanged<AppLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.language),
      title: const Text('Language'),
      subtitle: const Text('Only English is available right now.'),
      trailing: DropdownButton<AppLanguage>(
        value: current,
        onChanged: (v) => v == null ? null : onChanged(v),
        items: const [
          DropdownMenuItem(
            value: AppLanguage.english,
            child: Text('English'),
          ),
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
              leading: Icon(
                Icons.lightbulb,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(appName),
              subtitle:
                  const Text('Desktop GUI for AttentioLight-1 devices.'),
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
              subtitle: const Text('github.com/anomalyco/attentio-desktop'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                final uri = Uri.parse(
                    'https://github.com/anomalyco/attentio-desktop');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Licences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: version,
              ),
            ),
          ],
        );
      },
    );
  }
}
