import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Holds the expiry time of the current fast-polling window (if any).
class DeviceRefreshNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void refresh() {
    state = DateTime.now().add(const Duration(seconds: 15));
  }
}

final deviceRefreshProvider =
    NotifierProvider<DeviceRefreshNotifier, DateTime?>(
  DeviceRefreshNotifier.new,
);

/// Polls [apiListDevicesFull] on an interval so device lists stay fresh even
/// without manual refresh. When [deviceRefreshProvider] indicates fast-polling,
/// the interval drops to 2 seconds for 15 seconds.
final devicesStreamProvider = StreamProvider<List<DeviceInfo>>((ref) async* {
  // Emit an initial value as quickly as possible, then continue polling.
  try {
    yield await apiListDevicesFull();
  } catch (_) {
    yield <DeviceInfo>[];
  }

  while (true) {
    final fastUntil = ref.read(deviceRefreshProvider);
    final isFast =
        fastUntil != null && DateTime.now().isBefore(fastUntil);
    final interval =
        isFast ? const Duration(seconds: 2) : const Duration(seconds: 5);
    await Future<void>.delayed(interval);
    try {
      yield await apiListDevicesFull();
    } catch (_) {
      // Swallow transient errors — next tick will try again.
    }
  }
});

/// Per-device live status stream. Polls [apiGetStatus] every two seconds for
/// the given serial. Use `ref.watch(deviceStatusStreamProvider(serial))`.
final deviceStatusStreamProvider =
    StreamProvider.family<DeviceStatus, String>((ref, serial) async* {
  // First tick ASAP.
  try {
    yield await apiGetStatus(serial: serial);
  } catch (e) {
    rethrow;
  }
  await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
    try {
      yield await apiGetStatus(serial: serial);
    } catch (_) {
      // Skip tick; next poll retries.
    }
  }
});

/// One-shot lookup of device status (used by detail pages that also accept a
/// manual refresh button).
final deviceStatusProvider =
    FutureProvider.family<DeviceStatus, String>((ref, serial) async {
  return apiGetStatus(serial: serial);
});

/// Device metadata — read-only descriptor key/value pairs.
final deviceMetadataProvider =
    FutureProvider.family<List<KvEntry>, String>((ref, serial) async {
  return apiGetMetadata(serial: serial);
});

/// Persistent device settings (key/value pairs in flash).
final deviceSettingsProvider =
    FutureProvider.family<List<KvEntry>, String>((ref, serial) async {
  return apiSettingsList(serial: serial);
});
