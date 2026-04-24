import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Polls [apiListDevicesFull] on an interval so device lists stay fresh even
/// without manual refresh. Emits a new list on every tick.
final devicesStreamProvider = StreamProvider<List<DeviceInfo>>((ref) async* {
  // Emit an initial value as quickly as possible, then continue polling.
  try {
    yield await apiListDevicesFull();
  } catch (_) {
    yield <DeviceInfo>[];
  }
  final timer = Stream.periodic(const Duration(seconds: 5));
  await for (final _ in timer) {
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
