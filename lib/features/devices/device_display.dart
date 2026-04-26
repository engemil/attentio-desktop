import 'package:attentio_desktop/src/rust/api/device_api.dart';

/// Canonical display name for a device.
///
/// Priority:
///   1. User-assigned `device_name` setting (`DeviceInfo.name`), when non-empty.
///   2. USB iProduct descriptor (`DeviceInfo.deviceType`).
///   3. Generic literal fallback `"AttentioLight-1"`.
///
/// Used by the Overview, Devices list, and Device Detail pages so every page
/// shows the same label for the same device.
String deviceDisplayName(DeviceInfo d) {
  final name = d.name;
  if (name != null && name.isNotEmpty) return name;
  return d.deviceType ?? 'AttentioLight-1';
}
