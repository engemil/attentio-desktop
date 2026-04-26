import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/features/devices/device_display.dart';
import 'package:attentio_desktop/features/devices/devices_providers.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';

const _controlModeNames = ['STANDALONE', 'REMOTE'];
const _systemStateNames = [
  'BOOT',
  'POWERUP',
  'ACTIVE',
  'POWERDOWN',
  'OFF',
];
const _standaloneModeNames = [
  'Solid Color',
  'Brightness',
  'Blinking',
  'Pulsation',
  'Effects',
  'Traffic Light',
  'Night Light',
];
const _interfaceNames = ['NONE', 'STANDALONE', 'USB', 'BLE', 'WiFi'];

String _nameAt(List<String> names, int i) =>
    (i >= 0 && i < names.length) ? names[i] : 'UNKNOWN ($i)';

/// Width threshold (in logical pixels) at which the status header switches
/// from a stacked layout (identity above, status below) to a side-by-side
/// layout (identity left, status grid right).
const double _kStatusHeaderWideBreakpoint = 640;

/// Full-screen per-device control panel.
class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({super.key, required this.device});

  final DeviceInfo device;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  Color _pickedColor = Colors.white;
  double _brightness = 100;
  bool _busy = false;

  String get _serial => widget.device.serial;

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMsg)),
        );
      }
      // Kick the live status stream to reflect changes quickly.
      ref.invalidate(deviceStatusStreamProvider(_serial));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final isNormal = device.mode == 'Normal';
    // Only watch the status stream when in normal mode. The provider yields
    // `DeviceStatus` (non-nullable), so we type AsyncValue accordingly. For
    // non-normal devices we never render the header swatch as live — a grey
    // placeholder is used instead via `AsyncValue.loading()`.
    final AsyncValue<DeviceStatus> statusAsync = isNormal
        ? ref.watch(deviceStatusStreamProvider(_serial))
        : const AsyncValue<DeviceStatus>.loading();

    final displayName = deviceDisplayName(device);

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _StatusHeader(device: device, statusAsync: statusAsync),
            const SizedBox(height: 16),
            if (!isNormal)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Device is not in normal mode. AP protocol controls are '
                    'unavailable until the device exits bootloader mode.',
                  ),
                ),
              )
            else ...[
              _QuickActionsCard(
                onClaim: () =>
                    _run(() => apiClaim(serial: _serial), 'Claimed'),
                onRelease: () =>
                    _run(() => apiRelease(serial: _serial), 'Released'),
                onPowerOn: () => _run(
                    () => apiPowerOn(serial: _serial), 'Power on'),
                onPowerOff: () => _run(
                    () => apiPowerOff(serial: _serial), 'Power off'),
                onPing: () => _run(
                  () async {
                    final ms = await apiPing(serial: _serial);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ping: ${ms}ms')),
                      );
                    }
                  },
                  'Ping OK',
                ),
              ),
              const SizedBox(height: 16),
              _ControlsCard(
                pickedColor: _pickedColor,
                brightness: _brightness,
                onColorChanged: (c) => setState(() => _pickedColor = c),
                onBrightnessChanged: (v) => setState(() => _brightness = v),
                onLedOff: () =>
                    _run(() => apiLedOff(serial: _serial), 'LED off'),
                onSetColor: () => _run(
                  () => apiSetRgb(
                    serial: _serial,
                    // ignore: deprecated_member_use
                    r: _pickedColor.red,
                    // ignore: deprecated_member_use
                    g: _pickedColor.green,
                    // ignore: deprecated_member_use
                    b: _pickedColor.blue,
                  ),
                  'Colour applied',
                ),
                onSetBrightness: () => _run(
                  () => apiSetBrightness(
                      serial: _serial, brightness: _brightness.round()),
                  'Brightness applied',
                ),
              ),
              const SizedBox(height: 16),
              _DeviceSettingsCard(serial: _serial),
              const SizedBox(height: 16),
              _MetadataCard(serial: _serial),
            ],
          ],
        ),
      ),
    );
  }
}

/// Top-of-page status header. Shows the live colour swatch, device identity
/// (name / serial / mode chip / device type / USB location), and the full
/// 7-field live status grid. Adapts to a stacked layout on narrow windows.
class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.device, required this.statusAsync});

  final DeviceInfo device;
  final AsyncValue<DeviceStatus> statusAsync;

  @override
  Widget build(BuildContext context) {
    final Color swatch = statusAsync.maybeWhen(
      data: (s) => Color.fromARGB(255, s.currentR, s.currentG, s.currentB),
      orElse: () => Colors.grey.shade400,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= _kStatusHeaderWideBreakpoint;
            final identity = _IdentityBlock(device: device, swatch: swatch);
            final status = _LiveStatusBlock(statusAsync: statusAsync);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: identity),
                  const SizedBox(width: 24),
                  Expanded(flex: 5, child: status),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                status,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.device, required this.swatch});

  final DeviceInfo device;
  final Color swatch;

  @override
  Widget build(BuildContext context) {
    final displayName = deviceDisplayName(device);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: swatch,
            shape: BoxShape.circle,
            border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: const Icon(Icons.lightbulb,
              size: 36, color: Colors.white70),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: Theme.of(context).textTheme.headlineSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              _ModeChip(mode: device.mode),
              const SizedBox(height: 8),
              if (device.deviceType != null)
                Text(
                  device.deviceType!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              SelectableText(
                'Serial: ${device.serial}',
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 1,
              ),
              if (device.usbLocation != null)
                Text(
                  device.usbLocation!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveStatusBlock extends StatelessWidget {
  const _LiveStatusBlock({required this.statusAsync});

  final AsyncValue<DeviceStatus> statusAsync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Live Status',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        statusAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text('Error: $e'),
          data: (s) {
            final claimed = s.controlMode == 1; // 1 = REMOTE
            final iface = _nameAt(_interfaceNames, s.activeController);
            final rows = <MapEntry<String, Widget>>[
              MapEntry('Claimed', _ClaimChip(
                claimed: claimed,
                iface: iface,
                sessionId: s.sessionId,
              )),
              MapEntry('System state',
                  Text(_nameAt(_systemStateNames, s.systemState),
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Control mode',
                  Text(_nameAt(_controlModeNames, s.controlMode),
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Active controller',
                  Text(iface,
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Standalone mode',
                  Text(_nameAt(_standaloneModeNames, s.standaloneMode),
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Current colour (R, G, B)',
                  Text('(${s.currentR}, ${s.currentG}, ${s.currentB})',
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Brightness',
                  Text('${s.brightness}%',
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
              MapEntry('Session ID',
                  Text(s.sessionId.toString(),
                      style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()]))),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            r.key,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        r.value,
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClaimChip extends StatelessWidget {
  const _ClaimChip({
    required this.claimed,
    required this.iface,
    required this.sessionId,
  });

  final bool claimed;
  final String iface;
  final int sessionId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    if (claimed) {
      bg = Colors.green.shade600;
      fg = Colors.white;
      icon = Icons.lock_outline;
      label = 'Claimed via $iface (session #$sessionId)';
    } else {
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
      icon = Icons.lock_open;
      label = 'Not claimed';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(color: fg, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    Color bg;
    switch (mode) {
      case 'Normal':
        bg = Colors.green.shade600;
        break;
      case 'Bootloader':
        bg = Colors.orange.shade700;
        break;
      default:
        bg = Colors.grey.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        mode,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard({
    required this.onClaim,
    required this.onRelease,
    required this.onPowerOn,
    required this.onPowerOff,
    required this.onPing,
  });

  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final VoidCallback onPowerOn;
  final VoidCallback onPowerOff;
  final VoidCallback onPing;

  @override
  Widget build(BuildContext context) {
    // Five buttons in three logical groups, ordered for the user's spec:
    //   1. Claim / Release  (highest emphasis pair)
    //   2. Power On / Power Off  (medium emphasis pair)
    //   3. Ping  (diagnostic — lowest emphasis, on its own row)
    //
    // Style follows Material 3's emphasis ladder:
    //   filled → tonal → outlined → text.
    final claimBtn = FilledButton.icon(
      onPressed: onClaim,
      icon: const Icon(Icons.lock_outline),
      label: const Text('Claim'),
    );
    final releaseBtn = OutlinedButton.icon(
      onPressed: onRelease,
      icon: const Icon(Icons.lock_open),
      label: const Text('Release'),
    );
    final powerOnBtn = FilledButton.icon(
      onPressed: onPowerOn,
      icon: const Icon(Icons.power_settings_new),
      label: const Text('Power On'),
    );
    final powerOffBtn = OutlinedButton.icon(
      onPressed: onPowerOff,
      icon: const Icon(Icons.bedtime),
      label: const Text('Power Off'),
    );
    final pingBtn = FilledButton.icon(
      onPressed: onPing,
      icon: const Icon(Icons.network_ping),
      label: const Text('Ping'),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Controls',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 360;
                if (wide) {
                  // Each row is a Wrap so a tight pair gracefully reflows
                  // instead of overflowing if labels are unusually long.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [claimBtn, releaseBtn],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [powerOnBtn, powerOffBtn],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [pingBtn],
                      ),
                    ],
                  );
                }
                // Narrow: stack one full-width button per row.
                final flat = [
                  claimBtn,
                  releaseBtn,
                  powerOnBtn,
                  powerOffBtn,
                  pingBtn,
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < flat.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      flat[i],
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({
    required this.pickedColor,
    required this.brightness,
    required this.onColorChanged,
    required this.onBrightnessChanged,
    required this.onLedOff,
    required this.onSetColor,
    required this.onSetBrightness,
  });

  final Color pickedColor;
  final double brightness;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onLedOff;
  final VoidCallback onSetColor;
  final VoidCallback onSetBrightness;

  static const _presetColors = <Color>[
    Colors.white,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.pink,
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('LED Controls',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            const Text('Colour'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _presetColors)
                  _ColorDot(
                    color: c,
                    // ignore: deprecated_member_use
                    selected: c.value == pickedColor.value,
                    onTap: () => onColorChanged(c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _ColorChannelSlider(
              label: 'R',
              // ignore: deprecated_member_use
              value: pickedColor.red.toDouble(),
              onChanged: (v) => onColorChanged(Color.fromARGB(
                255,
                v.round(),
                // ignore: deprecated_member_use
                pickedColor.green,
                // ignore: deprecated_member_use
                pickedColor.blue,
              )),
              activeColor: Colors.red,
            ),
            _ColorChannelSlider(
              label: 'G',
              // ignore: deprecated_member_use
              value: pickedColor.green.toDouble(),
              onChanged: (v) => onColorChanged(Color.fromARGB(
                255,
                // ignore: deprecated_member_use
                pickedColor.red,
                v.round(),
                // ignore: deprecated_member_use
                pickedColor.blue,
              )),
              activeColor: Colors.green,
            ),
            _ColorChannelSlider(
              label: 'B',
              // ignore: deprecated_member_use
              value: pickedColor.blue.toDouble(),
              onChanged: (v) => onColorChanged(Color.fromARGB(
                255,
                // ignore: deprecated_member_use
                pickedColor.red,
                // ignore: deprecated_member_use
                pickedColor.green,
                v.round(),
              )),
              activeColor: Colors.blue,
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final swatchAndHex = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: pickedColor,
                        border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      // ignore: deprecated_member_use
                      '#${pickedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    ),
                  ],
                );
                final ledOffBtn = OutlinedButton.icon(
                  onPressed: onLedOff,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: const Text('LED Off'),
                );
                final applyColorBtn = FilledButton.icon(
                  onPressed: onSetColor,
                  icon: const Icon(Icons.palette),
                  label: const Text('Apply colour'),
                );
                final wide = constraints.maxWidth >= 360;
                if (wide) {
                  return Row(
                    children: [
                      swatchAndHex,
                      const Spacer(),
                      ledOffBtn,
                      const SizedBox(width: 8),
                      applyColorBtn,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: swatchAndHex,
                    ),
                    const SizedBox(height: 8),
                    ledOffBtn,
                    const SizedBox(height: 8),
                    applyColorBtn,
                  ],
                );
              },
            ),
            const Divider(height: 32),
            Text('Brightness: ${brightness.round()}%'),
            Slider(
              value: brightness,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${brightness.round()}%',
              onChanged: onBrightnessChanged,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onSetBrightness,
                icon: const Icon(Icons.brightness_6),
                label: const Text('Apply brightness'),
              ),
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
      borderRadius: BorderRadius.circular(32),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 16, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: activeColor,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 32, child: Text(value.round().toString())),
      ],
    );
  }
}

class _MetadataCard extends ConsumerWidget {
  const _MetadataCard({required this.serial});

  final String serial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadataAsync = ref.watch(deviceMetadataProvider(serial));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Metadata',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(deviceMetadataProvider(serial)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            metadataAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Error: $e'),
              data: (entries) => _KvTable(entries: entries),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceSettingsCard extends ConsumerWidget {
  const _DeviceSettingsCard({required this.serial});

  final String serial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(deviceSettingsProvider(serial));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Device Settings',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(deviceSettingsProvider(serial)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            settingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Error: $e'),
              data: (entries) => _EditableKvList(
                entries: entries,
                onSave: (key, value) async {
                  try {
                    await apiSettingsSet(
                        serial: serial, key: key, value: value);
                    ref.invalidate(deviceSettingsProvider(serial));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved $key')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e')),
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KvTable extends StatelessWidget {
  const _KvTable({required this.entries});

  final List<KvEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const Text('(empty)');
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Text(e.key)),
                Expanded(
                  flex: 3,
                  child: SelectableText(
                    e.value,
                    style: const TextStyle(
                        fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EditableKvList extends StatefulWidget {
  const _EditableKvList({required this.entries, required this.onSave});

  final List<KvEntry> entries;
  final Future<void> Function(String key, String value) onSave;

  @override
  State<_EditableKvList> createState() => _EditableKvListState();
}

class _EditableKvListState extends State<_EditableKvList> {
  final Map<String, TextEditingController> _controllers = {};

  @override
  void didUpdateWidget(covariant _EditableKvList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-sync controllers when the underlying entries list changes.
    for (final e in widget.entries) {
      final c = _controllers[e.key];
      if (c == null) {
        _controllers[e.key] = TextEditingController(text: e.value);
      } else if (c.text != e.value && !c.selection.isValid) {
        c.text = e.value;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    for (final e in widget.entries) {
      _controllers[e.key] = TextEditingController(text: e.value);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const Text('(empty)');
    return Column(
      children: [
        for (final e in widget.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(e.key)),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _controllers[e.key],
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Save',
                  icon: const Icon(Icons.save),
                  onPressed: () => widget.onSave(
                    e.key,
                    _controllers[e.key]!.text,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
