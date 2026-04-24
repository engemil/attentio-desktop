import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/features/devices/device_detail_page.dart';
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
              Text(
                'Connected Devices',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh device list',
                onPressed: () {
                  ref.invalidate(devicesStreamProvider);
                },
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
    final statusAsync = isNormal
        ? ref.watch(deviceStatusStreamProvider(device.serial))
        : const AsyncValue<DeviceStatus?>.data(null);

    final name = device.name?.isNotEmpty == true
        ? device.name!
        : (device.deviceType ?? 'AttentioLight-1');

    final Color swatch = statusAsync.maybeWhen(
      data: (s) => s == null
          ? Colors.grey.shade500
          : Color.fromARGB(255, s.currentR, s.currentG, s.currentB),
      orElse: () => Colors.grey.shade400,
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('Serial: ${device.serial}',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (device.deviceType != null)
                      Text(
                        device.deviceType!,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
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
