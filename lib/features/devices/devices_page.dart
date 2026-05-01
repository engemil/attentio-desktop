import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/features/devices/device_detail_page.dart';
import 'package:attentio_desktop/features/devices/device_display.dart';
import 'package:attentio_desktop/features/devices/devices_providers.dart';
import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// List of every connected AL-1, each card opens a full-screen detail page
/// with live controls.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(devicesStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  'Connected Devices',
                  style: Theme.of(context).textTheme.headlineMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: devicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
              data: (devices) {
                if (devices.isEmpty) {
                  return const Center(
                    child: Text(
                      'No devices found. Ensure your AL-1 is connected.',
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _DeviceListCard(
                    device: devices[i],
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              DeviceDetailPage(device: devices[i]),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceListCard extends ConsumerWidget {
  const _DeviceListCard({required this.device, required this.onTap});

  final DeviceInfo device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNormal = device.mode == 'Normal';

    final name = deviceDisplayName(device);

    // Watch the per-device status stream for the swatch colour. The provider
    // yields `DeviceStatus` (non-nullable), so we must handle the AsyncValue
    // as non-nullable to avoid a silent type mismatch.
    Color swatch = Colors.grey.shade500;
    if (isNormal) {
      final statusAsync = ref.watch(deviceStatusStreamProvider(device.serial));
      swatch = statusAsync.maybeWhen(
        data: (s) =>
            Color.fromARGB(255, s.currentR, s.currentG, s.currentB),
        orElse: () => Colors.grey.shade400,
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: const Icon(Icons.lightbulb,
                    size: 20, color: Colors.white70),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis),
                    if (device.deviceType != null)
                      Text(
                        device.deviceType!,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    Text('Serial: ${device.serial}',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              _ModeChip(mode: device.mode),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
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
