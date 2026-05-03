import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/ui/pages/device_detail_page.dart';
import 'package:attentio_desktop/ui/utils/device_display.dart';
import 'package:attentio_desktop/providers/devices_providers.dart';
import 'package:attentio_desktop/ui/pages/settings_page.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';
import 'package:attentio_desktop/ui/utils/responsive.dart';

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

    final settingsButton = SizedBox(
      height: 64,
      width: 64,
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
            child: Icon(Icons.settings, size: 28),
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
            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    cards[i],
                  ],
                  const SizedBox(height: 8),
                  settingsButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12),
                Expanded(child: cards[1]),
                const SizedBox(width: 12),
                Expanded(child: cards[2]),
                const SizedBox(width: 12),
                settingsButton,
              ],
            );
          },
        ),
        const SizedBox(height: 24),
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
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall,
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
    // Only query detailed status for devices that are in normal mode; in
    // bootloader mode the AP protocol isn't available.
    final isNormal = device.mode == 'Normal';
    final statusAsync = isNormal
        ? ref.watch(deviceStatusStreamProvider(device.serial))
        : const AsyncValue<DeviceStatus?>.data(null);

    final name = deviceDisplayName(device);

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
            children: [
              _ColorSwatch(statusAsync: statusAsync),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (device.deviceType != null)
                      Text(
                        device.deviceType!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      'Serial Number: ${device.serial}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (device.usbLocation != null)
                      Text(
                        'USB: ${device.usbLocation!}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (device.serialPort != null ||
                        device.protocolPort != null)
                      Text(
                        [
                          if (device.serialPort != null)
                            'Serial Data: ${device.serialPort!}',
                          if (device.protocolPort != null)
                            'Protocol: ${device.protocolPort!}',
                        ].join('  |  '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              _ModeBadge(mode: device.mode),
              if (isNormal && !isCompactWidth(context)) ...[
                const SizedBox(width: 12),
                _StatusSummary(statusAsync: statusAsync),
              ],
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
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
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 1,
        ),
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
    return statusAsync.when(
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => const Icon(Icons.error_outline, color: Colors.redAccent),
      data: (s) {
        if (s == null) return const SizedBox.shrink();
        final mode = s.controlMode == 0 ? 'Standalone' : 'Remote';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
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
