import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/ui/pages/device_detail_page.dart';
import 'package:attentio_desktop/ui/utils/device_display.dart';
import 'package:attentio_desktop/providers/devices_providers.dart';
import 'package:attentio_desktop/ui/pages/settings_page.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';
import 'package:attentio_desktop/providers/presets_provider.dart';

/// Top-level status summary across all connected AL-1 devices.
///
/// Read-only. Auto-refreshes via [devicesStreamProvider]. Per-device cards
/// show a colour swatch derived from the live [DeviceStatus] stream.
class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: devicesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (devices) => _OverviewBody(devices: devices),
      ),
    );
  }
}

class _OverviewBody extends ConsumerWidget {
  const _OverviewBody({required this.devices});

  final List<DeviceInfo> devices;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normal = devices.where((d) => d.mode == 'Normal').length;
    final bootloader = devices.where((d) => d.mode == 'Bootloader').length;

    final settingsButton = AspectRatio(
      aspectRatio: 1,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsPage(),
              ),
            );
          },
          child: const Center(
            child: Icon(Icons.settings, size: 22),
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cards = [
              _SummaryCard(
                icon: Icons.devices_other,
                label: 'Connected',
                value: devices.length.toString(),
                color: Theme.of(context).colorScheme.primary,
              ),
              _SummaryCard(
                icon: Icons.check_circle_outline,
                label: 'Normal',
                value: normal.toString(),
                color: Colors.green,
              ),
              _SummaryCard(
                icon: Icons.memory,
                label: 'Bootloader',
                value: bootloader.toString(),
                color: Colors.orange,
              ),
            ];
            // Below ~520 px the three cards crowd; stack them with Wrap so
            // each card takes the full row.
            if (constraints.maxWidth < 580) {
              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 6),
                        settingsButton,
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: cards[1]),
                      const SizedBox(width: 6),
                      Expanded(child: cards[2]),
                    ],
                  ),
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[2]),
                  const SizedBox(width: 8),
                  settingsButton,
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              'Devices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(width: 8),
            _RefreshButton(),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: devices.isEmpty
              ? const Center(
                  child: Text(
                    'No devices detected. Ensure your AL-1 is connected.',
                  ),
                )
              : Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) =>
                        _OverviewDeviceTile(device: devices[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row showing name, serial, mode, and a live colour swatch for a
/// single device on the overview page.
class _OverviewDeviceTile extends ConsumerWidget {
  const _OverviewDeviceTile({required this.device});

  final DeviceInfo device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNormal = device.mode == 'Normal';
    final statusAsync = isNormal
        ? ref.watch(deviceStatusStreamProvider(device.serial))
        : const AsyncValue<DeviceStatus?>.data(null);

    final name = deviceDisplayName(device);

    final favorites = isNormal
        ? ref.watch(deviceFavoritePresetsProvider(device.serial))
        : <DevicePreset>[];

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => DeviceDetailPage(device: device),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Three layout tiers based on available content width.
                    // Wide (>= 520): single row with everything inline.
                    // Medium (>= 350): two rows — text on top, presets+badge+status below.
                    // Compact (< 350): three rows — text, presets, badge+status.
                    final w = constraints.maxWidth;

                    if (w >= 650) {
                      return Row(
                        children: [
                          _ColorSwatch(statusAsync: statusAsync),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _DeviceTextColumn(
                              name: name,
                              device: device,
                            ),
                          ),
                          if (favorites.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            _FavoritePresetsRow(
                              serial: device.serial,
                              favorites: favorites,
                            ),
                          ],
                          const SizedBox(width: 12),
                          _ModeBadge(mode: device.mode),
                          if (isNormal) ...[
                            const SizedBox(width: 12),
                            _StatusSummary(statusAsync: statusAsync),
                          ],
                        ],
                      );
                    }

                    if (w >= 350) {
                      // Medium: two rows.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              _ColorSwatch(statusAsync: statusAsync),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _DeviceTextColumn(
                                  name: name,
                                  device: device,
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 48, top: 8),
                            child: Row(
                              children: [
                                if (favorites.isNotEmpty) ...[
                                  Flexible(
                                    child: _FavoritePresetsRow(
                                      serial: device.serial,
                                      favorites: favorites,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                _ModeBadge(mode: device.mode),
                                if (isNormal) ...[
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: _StatusSummary(
                                        statusAsync: statusAsync),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                    }

                    // Compact: three rows.
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _ColorSwatch(statusAsync: statusAsync),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _DeviceTextColumn(
                                name: name,
                                device: device,
                              ),
                            ),
                          ],
                        ),
                        if (favorites.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 48, top: 8),
                            child: _FavoritePresetsRow(
                              serial: device.serial,
                              favorites: favorites,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(left: 48, top: 8),
                          child: Row(
                            children: [
                              _ModeBadge(mode: device.mode),
                              if (isNormal) ...[
                                const SizedBox(width: 12),
                                Flexible(
                                  child: _StatusSummary(
                                      statusAsync: statusAsync),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// Device name, type, serial, USB location, and port info as a vertical
/// text column. Extracted so it can be reused in both wide and narrow layouts.
class _DeviceTextColumn extends StatelessWidget {
  const _DeviceTextColumn({
    required this.name,
    required this.device,
  });

  final String name;
  final DeviceInfo device;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (device.deviceType != null)
          Text(
            device.deviceType!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
      ],
    );
  }
}

/// Row of up to 4 favourite preset squares shown on the overview device tile.
/// Tapping a square immediately applies that preset to the device.
class _FavoritePresetsRow extends ConsumerWidget {
  const _FavoritePresetsRow({
    required this.serial,
    required this.favorites,
  });

  final String serial;
  final List<DevicePreset> favorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      clipBehavior: Clip.hardEdge,
      children: [
        for (final preset in favorites)
          _FavoritePresetDot(
            preset: preset,
            onTap: () => _applyPreset(context, ref, preset),
          ),
      ],
    );
  }

  Future<void> _applyPreset(
      BuildContext context, WidgetRef ref, DevicePreset preset) async {
    try {
      await apiSetRgb(serial: serial, r: preset.r, g: preset.g, b: preset.b);
      await apiSetBrightness(serial: serial, brightness: preset.brightness);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Preset "${preset.name}" applied'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to apply preset: $e')),
        );
      }
    }
  }
}

class _FavoritePresetDot extends StatelessWidget {
  const _FavoritePresetDot({
    required this.preset,
    required this.onTap,
  });

  final DevicePreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.fromARGB(255, preset.r, preset.g, preset.b);
    return Tooltip(
      message: '${preset.name} (${preset.brightness}%)',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
              width: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.statusAsync});

  final AsyncValue<DeviceStatus?> statusAsync;

  @override
  Widget build(BuildContext context) {
    final Color color = statusAsync.maybeWhen(
      data: (s) => s == null
          ? Colors.grey.shade500
          : Color.fromARGB(255, s.currentR, s.currentG, s.currentB),
      orElse: () => Colors.grey.shade400,
    );
    // Light head: 32x32 rounded square with device color (at top).
    // Base: 40x10 neutral rounded rectangle at bottom, drawn in front.
    // Total height: 26 + 10 - 4 = 32.
    return SizedBox(
      width: 40,
      height: 32,
      child: Stack(
        children: [
          // Light head (behind, at top)
          Positioned(
            top: 0,
            left: 4, // (40 - 32) / 2
            child: Container(
              width: 32,
              height: 26,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
          ),
          // Base (in front, at bottom)
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: 40,
              height: 10,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode});

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

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({required this.statusAsync});

  final AsyncValue<DeviceStatus?> statusAsync;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: statusAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, __) => const Icon(Icons.error_outline, color: Colors.redAccent),
        data: (s) {
          if (s == null) return const SizedBox.shrink();
          final mode = s.controlMode == 0 ? 'Standalone' : 'Remote';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(mode, style: Theme.of(context).textTheme.labelMedium),
              Text(
                'Brightness ${s.brightness}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Refresh button that triggers a 15-second fast-polling burst.
/// Shows a spinning icon and countdown while active.
class _RefreshButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends ConsumerState<_RefreshButton> {
  Timer? _uiTimer;
  int _secondsLeft = 0;

  void _startRefresh() {
    ref.read(deviceRefreshProvider.notifier).refresh();
    ref.invalidate(devicesStreamProvider);
    setState(() => _secondsLeft = 15);
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final fastUntil = ref.read(deviceRefreshProvider);
      if (fastUntil == null || DateTime.now().isAfter(fastUntil)) {
        timer.cancel();
        if (mounted) setState(() => _secondsLeft = 0);
        return;
      }
      final remaining =
          fastUntil.difference(DateTime.now()).inSeconds.clamp(0, 15);
      if (mounted) setState(() => _secondsLeft = remaining);
    });
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _secondsLeft > 0;
    return TextButton.icon(
      onPressed: _startRefresh,
      icon: isActive
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : const Icon(Icons.refresh, size: 20),
      label: Text(isActive ? 'Refreshing (${_secondsLeft}s)' : 'Refresh'),
    );
  }
}
