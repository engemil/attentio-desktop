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

/// Whether Bluetooth (BLE) discovery is enabled. When off, no BLE scan runs
/// and any previously-discovered BLE devices are dropped from the list.
/// Defaults off so USB-only setups are unaffected.
class BleEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final bleEnabledProvider =
    NotifierProvider<BleEnabledNotifier, bool>(BleEnabledNotifier.new);

/// Result of the most recent BLE scan, plus an in-flight flag for the UI.
class BleScanState {
  const BleScanState({this.devices = const [], this.scanning = false});

  final List<DeviceInfo> devices;
  final bool scanning;

  BleScanState copyWith({List<DeviceInfo>? devices, bool? scanning}) =>
      BleScanState(
        devices: devices ?? this.devices,
        scanning: scanning ?? this.scanning,
      );
}

/// Holds BLE-discovered devices. Populated on demand by [scan] (the "Discover"
/// button, when BLE is armed), since a BLE scan is slow (~3 s) and must stay
/// off the USB device-poll hot path.
class BleScanNotifier extends Notifier<BleScanState> {
  @override
  BleScanState build() => const BleScanState();

  /// Run a one-shot BLE scan and replace the cached results. Best-effort:
  /// any failure (no adapter, etc.) leaves the previous results untouched.
  Future<void> scan() async {
    if (state.scanning) return;
    state = state.copyWith(scanning: true);
    try {
      final found = await apiScanBle();
      state = BleScanState(devices: found, scanning: false);
    } catch (_) {
      state = state.copyWith(scanning: false);
    }
  }

  /// Drop all BLE results (called when Bluetooth is toggled off).
  void clear() => state = const BleScanState();
}

final bleScanProvider =
    NotifierProvider<BleScanNotifier, BleScanState>(BleScanNotifier.new);

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
