import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/src/rust/api/monitor_api.dart';

/// Live stream of serial debug lines (CDC0) for a device.
///
/// Returns a `Stream<String>` that emits one line at a time. The stream
/// auto-reconnects on errors and runs until the subscription is cancelled.
final serialMonitorStreamProvider =
    StreamProvider.family<String, String>((ref, serial) {
  return apiMonitorSerialStart(serial: serial);
});

/// Live stream of AP protocol traffic (CDC1) for a device.
///
/// Returns formatted strings like "→ SET_RGB [R:255 G:0 B:0]" and
/// "← OK [FF 00 00]". The stream taps into the shared ApClient's
/// broadcast channel.
final protocolMonitorStreamProvider =
    StreamProvider.family<String, String>((ref, serial) {
  return apiMonitorProtocolStart(serial: serial);
});
