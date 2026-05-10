import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Holds the expiry time of the current fast-polling window (if any).
///
/// The Rust-side device list stream owns its own deadline (set via
/// `apiDevicesRequestFastRefresh`); this notifier mirrors it so UI badges
/// (e.g. a "refreshing" indicator) can still observe whether fast-polling
/// is active.
class DeviceRefreshNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void refresh() {
    state = DateTime.now().add(const Duration(seconds: 15));
    // Tell the long-lived Rust poll loop to switch to the 2-second cadence.
    apiDevicesRequestFastRefresh();
  }
}

final deviceRefreshProvider =
    NotifierProvider<DeviceRefreshNotifier, DateTime?>(
  DeviceRefreshNotifier.new,
);

/// Live device list, fed by a long-lived Rust task that polls
/// `find_devices()` internally and pushes updates over a `StreamSink`.
///
/// Replaces a previous Dart-side `Stream.periodic` loop that spawned a fresh
/// `apiListDevicesFull` future every tick. That pattern caused
/// "Fail to post message to Dart" warnings whenever Riverpod auto-disposed
/// the provider (or its watchers rebuilt) while a Rust future was in flight.
final devicesStreamProvider = StreamProvider<List<DeviceInfo>>((ref) {
  return apiDevicesStreamStart();
});

/// Per-device live status stream, fed by a long-lived Rust task that polls
/// `get_status` every 2 s and pushes updates over a `StreamSink`. See
/// [devicesStreamProvider] for the rationale.
///
/// Use `ref.watch(deviceStatusStreamProvider(serial))`.
final deviceStatusStreamProvider =
    StreamProvider.family<DeviceStatus, String>((ref, serial) {
  return apiDeviceStatusStreamStart(serial: serial);
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
