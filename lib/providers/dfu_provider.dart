import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:attentio_desktop/src/rust/api/device_api.dart';
import 'package:attentio_desktop/providers/devices_providers.dart';

class DfuState {
  const DfuState({this.serial, this.progress, this.deviceInfo});

  final String? serial;
  final DfuProgress? progress;
  final DeviceInfo? deviceInfo;

  bool get isActive =>
      serial != null &&
      progress != null &&
      progress!.phase != 'done' &&
      progress!.phase != 'error';
}

class DfuNotifier extends Notifier<DfuState> {
  StreamSubscription<DfuProgress>? _sub;

  @override
  DfuState build() {
    ref.onDispose(() => _sub?.cancel());
    return const DfuState();
  }

  void startFlash(String serial, String firmwarePath, DeviceInfo deviceInfo) {
    if (state.isActive) return;
    _sub?.cancel();
    state = DfuState(
      serial: serial,
      progress: DfuProgress(
        phase: 'validating',
        bytesWritten: BigInt.zero,
        bytesTotal: BigInt.zero,
      ),
      deviceInfo: deviceInfo,
    );
    _sub = apiFlashFirmware(serial: serial, firmwarePath: firmwarePath).listen(
      (event) {
        state = DfuState(serial: serial, progress: event, deviceInfo: deviceInfo);
        if (event.phase == 'done') {
          ref.invalidate(deviceMetadataProvider(serial));
          _sub = null;
        } else if (event.phase == 'error') {
          _sub = null;
        }
      },
      onError: (e) {
        state = DfuState(
          serial: serial,
          progress: DfuProgress(
            phase: 'error',
            bytesWritten: BigInt.zero,
            bytesTotal: BigInt.zero,
            errorMessage: e.toString(),
          ),
          deviceInfo: deviceInfo,
        );
        _sub = null;
      },
    );
  }

  void dismiss() {
    _sub?.cancel();
    _sub = null;
    state = const DfuState();
  }
}

final dfuProvider = NotifierProvider<DfuNotifier, DfuState>(DfuNotifier.new);
