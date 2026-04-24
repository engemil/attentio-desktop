import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final statusAsync = isNormal
        ? ref.watch(deviceStatusStreamProvider(_serial))
        : const AsyncValue<DeviceStatus?>.data(null);

    final displayName = device.name?.isNotEmpty == true
        ? device.name!
        : (device.deviceType ?? 'AttentioLight-1');

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            icon: const Icon(Icons.refresh),
            onPressed: _busy
                ? null
                : () =>
                    ref.invalidate(deviceStatusStreamProvider(_serial)),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _HeaderCard(device: device, statusAsync: statusAsync),
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
              _ControlsCard(
                pickedColor: _pickedColor,
                brightness: _brightness,
                onColorChanged: (c) => setState(() => _pickedColor = c),
                onBrightnessChanged: (v) => setState(() => _brightness = v),
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
                onLedOff: () =>
                    _run(() => apiLedOff(serial: _serial), 'LEDs off'),
              ),
              const SizedBox(height: 16),
              _PowerControlCard(
                onPowerOn: () => _run(
                    () => apiPowerOn(serial: _serial), 'Power on'),
                onPowerOff: () => _run(
                    () => apiPowerOff(serial: _serial), 'Power off'),
                onClaim: () =>
                    _run(() => apiClaim(serial: _serial), 'Claimed'),
                onRelease: () =>
                    _run(() => apiRelease(serial: _serial), 'Released'),
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
              _StatusCard(statusAsync: statusAsync),
              const SizedBox(height: 16),
              _MetadataCard(serial: _serial),
              const SizedBox(height: 16),
              _DeviceSettingsCard(serial: _serial),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.device, required this.statusAsync});

  final DeviceInfo device;
  final AsyncValue<DeviceStatus?> statusAsync;

  @override
  Widget build(BuildContext context) {
    final Color swatch = statusAsync.maybeWhen(
      data: (s) => s == null
          ? Colors.grey.shade500
          : Color.fromARGB(255, s.currentR, s.currentG, s.currentB),
      orElse: () => Colors.grey.shade400,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: const Icon(Icons.lightbulb,
                  size: 32, color: Colors.white70),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name?.isNotEmpty == true
                        ? device.name!
                        : 'AttentioLight-1',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  Text('Serial: ${device.serial}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  if (device.deviceType != null)
                    Text(device.deviceType!,
                        style: Theme.of(context).textTheme.bodySmall),
                  if (device.usbLocation != null)
                    Text(device.usbLocation!,
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
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
    required this.onSetColor,
    required this.onSetBrightness,
    required this.onLedOff,
  });

  final Color pickedColor;
  final double brightness;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onBrightnessChanged;
  final VoidCallback onSetColor;
  final VoidCallback onSetBrightness;
  final VoidCallback onLedOff;

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
                    selected: c.value == pickedColor.value,
                    onTap: () => onColorChanged(c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
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
              ],
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
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: pickedColor,
                    border: Border.all(
                        color:
                            Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '#${pickedColor.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onSetColor,
                  icon: const Icon(Icons.palette),
                  label: const Text('Apply colour'),
                ),
              ],
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
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onLedOff,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: const Text('LEDs Off'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: onSetBrightness,
                  icon: const Icon(Icons.brightness_6),
                  label: const Text('Apply brightness'),
                ),
              ],
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

class _PowerControlCard extends StatelessWidget {
  const _PowerControlCard({
    required this.onPowerOn,
    required this.onPowerOff,
    required this.onClaim,
    required this.onRelease,
    required this.onPing,
  });

  final VoidCallback onPowerOn;
  final VoidCallback onPowerOff;
  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final VoidCallback onPing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Power & Session',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onPowerOn,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Power On'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onPowerOff,
                  icon: const Icon(Icons.bedtime),
                  label: const Text('Power Off'),
                ),
                OutlinedButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Claim'),
                ),
                OutlinedButton.icon(
                  onPressed: onRelease,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Release'),
                ),
                TextButton.icon(
                  onPressed: onPing,
                  icon: const Icon(Icons.network_ping),
                  label: const Text('Ping'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.statusAsync});

  final AsyncValue<DeviceStatus?> statusAsync;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Live Status',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            statusAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (s) {
                if (s == null) return const SizedBox.shrink();
                final rows = <MapEntry<String, String>>[
                  MapEntry('System state',
                      _nameAt(_systemStateNames, s.systemState)),
                  MapEntry('Control mode',
                      _nameAt(_controlModeNames, s.controlMode)),
                  MapEntry('Active controller',
                      _nameAt(_interfaceNames, s.activeController)),
                  MapEntry('Standalone mode',
                      _nameAt(_standaloneModeNames, s.standaloneMode)),
                  MapEntry(
                      'Current colour (R, G, B)',
                      '(${s.currentR}, ${s.currentG}, ${s.currentB})'),
                  MapEntry('Brightness', '${s.brightness}%'),
                  MapEntry('Session ID', s.sessionId.toString()),
                ];
                return Column(
                  children: [
                    for (final r in rows)
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(child: Text(r.key)),
                            Text(
                              r.value,
                              style: const TextStyle(fontFeatures: [
                                FontFeature.tabularFigures()
                              ]),
                            ),
                          ],
                        ),
                      ),
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

class _MetadataCard extends ConsumerWidget {
  const _MetadataCard({required this.serial});

  final String serial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metadataAsync = ref.watch(deviceMetadataProvider(serial));
    return Card(
      child: ExpansionTile(
        title: Text('Metadata',
            style: Theme.of(context).textTheme.titleMedium),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          metadataAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
            error: (e, _) => Text('Error: $e'),
            data: (entries) => _KvTable(entries: entries),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () =>
                  ref.invalidate(deviceMetadataProvider(serial)),
            ),
          ),
        ],
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
      child: ExpansionTile(
        title: Text('Device Settings',
            style: Theme.of(context).textTheme.titleMedium),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          settingsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: () =>
                  ref.invalidate(deviceSettingsProvider(serial)),
            ),
          ),
        ],
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
