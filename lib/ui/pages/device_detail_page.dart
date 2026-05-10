import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/ui/utils/device_display.dart';
import 'package:attentio_desktop/providers/devices_providers.dart';
import 'package:attentio_desktop/ui/widgets/preset_edit_dialog.dart';
import 'package:attentio_desktop/providers/presets_provider.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';
import 'package:attentio_desktop/ui/pages/monitor_page.dart';

const _controlModeNames = ['STANDALONE', 'REMOTE'];
const _systemStateNames = ['BOOT', 'POWERUP', 'ACTIVE', 'POWERDOWN', 'OFF'];
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
const double _kStatusHeaderWideBreakpoint = 750;

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

  // ── DFU flash state ────────────────────────────────────────────────────────
  // Held at page level so the subscription survives device mode changes.
  // When the device enters bootloader mid-flash, the page rebuilds but this
  // state stays alive, keeping the progress stream connected.
  DfuProgress? _dfuProgress;
  StreamSubscription<DfuProgress>? _dfuSub;
  String? _selectedFirmwarePath;

  bool get _isFlashing =>
      _dfuProgress != null &&
      _dfuProgress!.phase != 'done' &&
      _dfuProgress!.phase != 'error';

  @override
  void dispose() {
    _dfuSub?.cancel();
    super.dispose();
  }

  Future<void> _selectFirmware() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Firmware Binary',
      type: FileType.custom,
      allowedExtensions: ['bin'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    setState(() => _selectedFirmwarePath = path);
  }

  Future<void> _doFlash() async {
    final path = _selectedFirmwarePath;
    if (path == null) return;

    await _dfuSub?.cancel();
    setState(() {
      _selectedFirmwarePath = null;
      _dfuProgress = DfuProgress(
          phase: 'validating',
          bytesWritten: BigInt.zero,
          bytesTotal: BigInt.zero,
        );
    });

    _dfuSub = apiFlashFirmware(
      serial: _serial,
      firmwarePath: path, // path from _selectFirmware, cleared before starting
    ).listen(
      (event) {
        if (!mounted) return;
        setState(() => _dfuProgress = event);
        if (event.phase == 'done') {
          ref.invalidate(deviceMetadataProvider(_serial));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Firmware flashed successfully.')),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) setState(() => _dfuProgress = null);
          });
        } else if (event.phase == 'error') {
          final msg = event.errorMessage ?? 'Unknown error';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Flash failed: $msg')),
          );
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted) setState(() => _dfuProgress = null);
          });
        }
      },
      onError: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Flash error: $e')),
        );
        setState(() => _dfuProgress = null);
      },
    );
  }

  String _phaseLabel(DfuProgress p) {
    switch (p.phase) {
      case 'validating':
        return 'Validating firmware file…';
      case 'entering_bootloader':
        return 'Entering bootloader…';
      case 'erasing':
        return 'Erasing flash…';
      case 'flashing':
        final pct = p.bytesTotal > BigInt.zero
            ? (p.bytesWritten * BigInt.from(100) ~/ p.bytesTotal).toInt()
            : 0;
        return 'Flashing firmware ($pct%)';
      case 'rebooting':
        return 'Waiting for device to reboot…';
      case 'done':
        return 'Done';
      case 'error':
        return 'Error: ${p.errorMessage ?? 'unknown'}';
      default:
        return p.phase;
    }
  }

  double? _progressValue(DfuProgress p) {
    if (p.phase == 'flashing' && p.bytesTotal > BigInt.zero) {
      return p.bytesWritten.toDouble() / p.bytesTotal.toDouble();
    }
    return null;
  }
  // ── end DFU flash state ────────────────────────────────────────────────────

  String get _serial => widget.device.serial;

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMsg)));
      }
      // Kick the live status stream to reflect changes quickly.
      // We do NOT use `ref.invalidate(deviceStatusStreamProvider(_serial))`
      // here: invalidating a stream-backed provider tears down and respawns
      // the underlying Rust task, and FRB emits one
      // "Fail to post message to Dart" warning per close-sentinel that races
      // with port disposal. `apiDeviceStatusKick` instead wakes the existing
      // poll loop early so it issues a fresh `get_status()` immediately —
      // same UX, no stream churn.
      apiDeviceStatusKick(serial: _serial);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the device stream so the page rebuilds when device info changes
    // (e.g. after a rename). Fall back to the static widget.device if the
    // device disappears from the stream momentarily.
    final devicesAsync = ref.watch(devicesStreamProvider);
    // Freeze to the initial snapshot during DFU so the mode chip and status
    // block don't cycle as the device alternates between Normal/Bootloader.
    final device = _isFlashing
        ? widget.device
        : devicesAsync.whenData((devices) {
              try {
                return devices.firstWhere((d) => d.serial == _serial);
              } catch (_) {
                return widget.device;
              }
            }).value ??
            widget.device;

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
            if (_isFlashing)
              _FirmwareProgressCard(
                phaseLabel: _phaseLabel(_dfuProgress!),
                progressValue: _progressValue(_dfuProgress!),
              )
            else if (!isNormal)
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
                onClaim: () => _run(() => apiClaim(serial: _serial), 'Claimed'),
                onRelease: () =>
                    _run(() => apiRelease(serial: _serial), 'Released'),
                onPowerOn: () =>
                    _run(() => apiPowerOn(serial: _serial), 'Power on'),
                onPowerOff: () =>
                    _run(() => apiPowerOff(serial: _serial), 'Power off'),
                onPing: () => _run(() async {
                  final ms = await apiPing(serial: _serial);
                  if (mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Ping: ${ms}ms')));
                  }
                }, 'Ping OK'),
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
                    serial: _serial,
                    brightness: _brightness.round(),
                  ),
                  'Brightness applied',
                ),
              ),
              const SizedBox(height: 16),
              _PresetsCard(
                serial: _serial,
                deviceName: displayName,
                currentR: _pickedColor.red, // ignore: deprecated_member_use
                currentG: _pickedColor.green, // ignore: deprecated_member_use
                currentB: _pickedColor.blue, // ignore: deprecated_member_use
                currentBrightness: _brightness.round(),
                onApplyPreset: (preset) async {
                  setState(() {
                    _pickedColor = Color.fromARGB(
                      255,
                      preset.r,
                      preset.g,
                      preset.b,
                    );
                    _brightness = preset.brightness.toDouble();
                  });
                  await _run(() async {
                    await apiSetRgb(
                      serial: _serial,
                      r: preset.r,
                      g: preset.g,
                      b: preset.b,
                    );
                    await apiSetBrightness(
                      serial: _serial,
                      brightness: preset.brightness,
                    );
                  }, 'Preset "${preset.name}" applied');
                },
              ),
              const SizedBox(height: 16),
              _DeviceSettingsCard(serial: _serial, device: device),
              const SizedBox(height: 16),
              _FirmwareUpdateCard(
                selectedFilename: _selectedFirmwarePath?.split('/').last,
                onSelect: _selectFirmware,
                onFlash: _doFlash,
              ),
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

class _IdentityBlock extends ConsumerWidget {
  const _IdentityBlock({required this.device, required this.swatch});

  final DeviceInfo device;
  final Color swatch;

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: device.name ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null) return;
    try {
      await apiRenameDevice(serial: device.serial, name: newName);
      // Refresh device discovery and settings so the name updates everywhere.
      ref.invalidate(devicesStreamProvider);
      ref.invalidate(deviceSettingsProvider(device.serial));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newName.isEmpty
                  ? 'Device name cleared'
                  : 'Device renamed to "$newName"',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = deviceDisplayName(device);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AttentioLight product silhouette: light head + base.
        SizedBox(
          width: 88,
          height: 72,
          child: Stack(
            children: [
              // Light head (behind)
              Positioned(
                top: 0,
                left: 10, // (88 - 68) / 2 ≈ 10
                child: Container(
                  width: 68,
                  height: 56,
                  decoration: BoxDecoration(
                    color: swatch,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      topRight: Radius.circular(14),
                    ),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              // Base (in front, at bottom)
              Positioned(
                bottom: 0,
                left: 0,
                child: Container(
                  width: 88,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    tooltip: 'Rename device',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: () => _editName(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _ModeChip(mode: device.mode),
              const SizedBox(height: 8),
              if (device.deviceType != null)
                Text(
                  device.deviceType!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              SelectableText(
                'Serial Number: ${device.serial}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (device.usbLocation != null)
                Text(
                  'USB: ${device.usbLocation!}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.serialPort != null)
                Text(
                  'Serial Data Port: ${device.serialPort!}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (device.protocolPort != null)
                Text(
                  'Protocol Port: ${device.protocolPort!}',
                  style: Theme.of(context).textTheme.bodySmall,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Live Status',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        statusAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Text('Error: $e'),
          data: (s) {
            final claimed = s.controlMode == 1; // 1 = REMOTE
            final iface = _nameAt(_interfaceNames, s.activeController);
            final rows = <MapEntry<String, Widget>>[
              MapEntry(
                'Claimed',
                _ClaimChip(
                  claimed: claimed,
                  iface: iface,
                  sessionId: s.sessionId,
                ),
              ),
              MapEntry(
                'System state',
                Text(
                  _nameAt(_systemStateNames, s.systemState),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Control mode',
                Text(
                  _nameAt(_controlModeNames, s.controlMode),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Active controller',
                Text(
                  iface,
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Standalone mode',
                Text(
                  _nameAt(_standaloneModeNames, s.standaloneMode),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Current colour (R, G, B)',
                Text(
                  '(${s.currentR}, ${s.currentG}, ${s.currentB})',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Brightness',
                Text(
                  '${s.brightness}%',
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              MapEntry(
                'Session ID',
                Text(
                  s.sessionId.toString(),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
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
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: r.value),
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
            Text('Controls', style: Theme.of(context).textTheme.titleMedium),
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
                      Wrap(spacing: 12, runSpacing: 12, children: [pingBtn]),
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
            Text(
              'LED Controls',
              style: Theme.of(context).textTheme.titleMedium,
            ),
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
              onChanged: (v) => onColorChanged(
                Color.fromARGB(
                  255,
                  v.round(),
                  // ignore: deprecated_member_use
                  pickedColor.green,
                  // ignore: deprecated_member_use
                  pickedColor.blue,
                ),
              ),
              activeColor: Colors.red,
            ),
            _ColorChannelSlider(
              label: 'G',
              // ignore: deprecated_member_use
              value: pickedColor.green.toDouble(),
              onChanged: (v) => onColorChanged(
                Color.fromARGB(
                  255,
                  // ignore: deprecated_member_use
                  pickedColor.red,
                  v.round(),
                  // ignore: deprecated_member_use
                  pickedColor.blue,
                ),
              ),
              activeColor: Colors.green,
            ),
            _ColorChannelSlider(
              label: 'B',
              // ignore: deprecated_member_use
              value: pickedColor.blue.toDouble(),
              onChanged: (v) => onColorChanged(
                Color.fromARGB(
                  255,
                  // ignore: deprecated_member_use
                  pickedColor.red,
                  // ignore: deprecated_member_use
                  pickedColor.green,
                  v.round(),
                ),
              ),
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
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
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
                    Align(alignment: Alignment.centerLeft, child: swatchAndHex),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
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

class _PresetsCard extends ConsumerWidget {
  const _PresetsCard({
    required this.serial,
    required this.deviceName,
    required this.currentR,
    required this.currentG,
    required this.currentB,
    required this.currentBrightness,
    required this.onApplyPreset,
  });

  final String serial;
  final String deviceName;
  final int currentR;
  final int currentG;
  final int currentB;
  final int currentBrightness;
  final Future<void> Function(DevicePreset preset) onApplyPreset;

  Future<void> _saveAsPreset(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => PresetEditDialog(
        initialR: currentR,
        initialG: currentG,
        initialB: currentB,
        initialBrightness: currentBrightness,
      ),
    );
    if (result is DevicePreset) {
      final added = await ref
          .read(devicePresetsProvider(serial).notifier)
          .addPreset(result);
      if (!added && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Maximum of $kMaxPresets presets reached.'),
          ),
        );
      }
    }
  }

  Future<void> _editPreset(
    BuildContext context,
    WidgetRef ref,
    int index,
    DevicePreset preset,
  ) async {
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => PresetEditDialog(existing: preset, index: index),
    );
    if (result is PresetDeleteSentinel) {
      await ref
          .read(devicePresetsProvider(serial).notifier)
          .removePreset(index);
    } else if (result is DevicePreset) {
      await ref
          .read(devicePresetsProvider(serial).notifier)
          .updatePreset(index, result);
    }
  }

  Future<void> _exportConfig(BuildContext context, WidgetRef ref) async {
    final presets = ref.read(devicePresetsProvider(serial));

    // Read device_name from the device settings.
    String? deviceNameSetting;
    try {
      final settings = await apiSettingsList(serial: serial);
      for (final s in settings) {
        if (s.key == 'device_name') {
          deviceNameSetting = s.value;
          break;
        }
      }
    } catch (_) {
      // If we can't read settings, export without device_name.
    }

    final config = <String, dynamic>{
      'serial': serial,
      if (deviceNameSetting != null && deviceNameSetting.isNotEmpty)
        'device_name': deviceNameSetting,
      'presets': presets.map((p) => p.toJson()).toList(),
    };

    final json = const JsonEncoder.withIndent('  ').convert(config);

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Device Configuration',
      fileName:
          'attentio_${serial.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      await File(result).writeAsString(json);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuration exported.')),
        );
      }
    }
  }

  Future<void> _importConfig(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import Device Configuration',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    Map<String, dynamic> config;
    try {
      config =
          jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid configuration file: $e')),
        );
      }
      return;
    }

    final fileSerial = config['serial'] as String?;
    final fileDeviceName = config['device_name'] as String?;
    final presetsJson = config['presets'] as List<dynamic>?;
    final presets =
        presetsJson
            ?.map((e) => DevicePreset.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    // Build a confirmation message.
    String message;
    if (fileSerial == serial) {
      message =
          'Load configuration for "$deviceName"?\n\n'
          'This will overwrite the current ${ref.read(devicePresetsProvider(serial)).length} preset(s) '
          'with ${presets.length} preset(s) from the file.';
    } else {
      message =
          'This configuration was saved for device '
          '"${fileDeviceName ?? fileSerial ?? 'Unknown'}" '
          '(serial: ${fileSerial ?? 'unknown'}).\n\n'
          'Load it onto "$deviceName" (serial: $serial) instead?\n\n'
          'This will overwrite the current ${ref.read(devicePresetsProvider(serial)).length} preset(s) '
          'with ${presets.length} preset(s) from the file.';
    }

    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Configuration'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Apply presets.
    await ref.read(devicePresetsProvider(serial).notifier).replaceAll(presets);

    // Optionally apply device_name.
    if (fileDeviceName != null && fileDeviceName.isNotEmpty) {
      try {
        await apiSettingsSet(
          serial: serial,
          key: 'device_name',
          value: fileDeviceName,
        );
        // Refresh device discovery so the name updates.
        ref.invalidate(devicesStreamProvider);
      } catch (_) {
        // Non-critical — presets are already imported.
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${presets.length} preset(s).')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(devicePresetsProvider(serial));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Presets', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Import configuration',
                  icon: const Icon(Icons.file_open_outlined),
                  onPressed: () => _importConfig(context, ref),
                ),
                IconButton(
                  tooltip: 'Export configuration',
                  icon: const Icon(Icons.save_alt),
                  onPressed: () => _exportConfig(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (presets.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No presets yet. Use "Save as Preset" to capture the '
                  'current colour and brightness.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final crossCount = w >= 800
                      ? 6
                      : w >= 600
                      ? 5
                      : w >= 400
                      ? 4
                      : 3;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossCount,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: presets.length,
                    itemBuilder: (context, index) {
                      final p = presets[index];
                      final color = Color.fromARGB(255, p.r, p.g, p.b);
                      return _PresetTile(
                        preset: p,
                        color: color,
                        onTap: () => onApplyPreset(p),
                        onEdit: () => _editPreset(context, ref, index, p),
                        onToggleFavorite: () async {
                          final ok = await ref
                              .read(devicePresetsProvider(serial).notifier)
                              .toggleFavorite(index);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Maximum of $kMaxFavorites favourites reached.',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: presets.length >= kMaxPresets
                    ? null
                    : () => _saveAsPreset(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Save as Preset'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.color,
    required this.onTap,
    required this.onEdit,
    required this.onToggleFavorite,
  });

  final DevicePreset preset;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    // Determine if the color is light to pick contrasting icon/text colors.
    final luminance = color.computeLuminance();
    final fgColor = luminance > 0.4 ? Colors.black87 : Colors.white;
    final fgDim = luminance > 0.4 ? Colors.black54 : Colors.white70;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          children: [
            // Star (top-left)
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: Icon(
                  preset.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 22,
                  color: preset.isFavorite ? Colors.amber : fgDim,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onToggleFavorite,
                tooltip: preset.isFavorite
                    ? 'Remove from overview'
                    : 'Show on overview',
              ),
            ),
            // Edit (top-right)
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: Icon(Icons.edit, size: 18, color: fgDim),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onEdit,
                tooltip: 'Edit preset',
              ),
            ),
            // Bottom bar: name + brightness
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(60),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.name,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: fgColor),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${preset.brightness}%',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: fgDim),
                    ),
                  ],
                ),
              ),
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
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
  const _DeviceSettingsCard({required this.serial, required this.device});

  final String serial;
  final DeviceInfo device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(deviceSettingsProvider(serial));
    final displayName = deviceDisplayName(device);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Serial Logging and Monitoring',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MonitorPage(
                      serial: serial,
                      deviceName: displayName,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.terminal),
              label: const Text('Open Monitor'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Settings',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            settingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Error: $e'),
              data: (entries) => _EditableKvList(
                entries: entries.where((e) => e.key != 'device_name').toList(),
                onSave: (key, value) async {
                  try {
                    await apiSettingsSet(
                      serial: serial,
                      key: key,
                      value: value,
                    );
                    ref.invalidate(deviceSettingsProvider(serial));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Saved $key')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
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
                  onPressed: () =>
                      widget.onSave(e.key, _controllers[e.key]!.text),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ── Firmware Update Card (idle state) ────────────────────────────────────────

class _FirmwareUpdateCard extends StatelessWidget {
  const _FirmwareUpdateCard({
    required this.selectedFilename,
    required this.onSelect,
    required this.onFlash,
  });

  final String? selectedFilename;
  final VoidCallback onSelect;
  final VoidCallback onFlash;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Firmware Update',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (selectedFilename == null)
              FilledButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.folder_open),
                label: const Text('Select Firmware File…'),
              )
            else ...[
              Row(
                children: [
                  const Icon(Icons.description_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      selectedFilename!,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: onSelect,
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: onFlash,
                icon: const Icon(Icons.system_update),
                label: const Text('Flash Firmware'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Firmware Progress Card (shown during an active flash) ─────────────────────

class _FirmwareProgressCard extends StatelessWidget {
  const _FirmwareProgressCard({
    required this.phaseLabel,
    required this.progressValue,
  });

  final String phaseLabel;
  final double? progressValue; // null = indeterminate

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Firmware Update',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: progressValue,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(phaseLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Do not unplug the device.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
