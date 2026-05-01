import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Maximum number of presets a single device may hold.
const int kMaxPresets = 12;

/// A single colour + brightness preset for an AL-1 device.
@immutable
class DevicePreset {
  final String name;
  final int r;
  final int g;
  final int b;
  final int brightness; // 0-100

  const DevicePreset({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    required this.brightness,
  });

  DevicePreset copyWith({
    String? name,
    int? r,
    int? g,
    int? b,
    int? brightness,
  }) {
    return DevicePreset(
      name: name ?? this.name,
      r: r ?? this.r,
      g: g ?? this.g,
      b: b ?? this.b,
      brightness: brightness ?? this.brightness,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'r': r,
        'g': g,
        'b': b,
        'brightness': brightness,
      };

  factory DevicePreset.fromJson(Map<String, dynamic> json) => DevicePreset(
        name: json['name'] as String,
        r: json['r'] as int,
        g: json['g'] as int,
        b: json['b'] as int,
        brightness: json['brightness'] as int,
      );
}

/// SharedPreferences key for a device's presets list.
String _prefsKey(String serial) => 'presets.$serial';

/// Manages the list of [DevicePreset]s for a specific device (identified by
/// serial number). Persists to [SharedPreferences].
class DevicePresetsNotifier extends Notifier<List<DevicePreset>> {
  DevicePresetsNotifier(this.serial);

  final String serial;

  @override
  List<DevicePreset> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey(serial));
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => DevicePreset.fromJson(e as Map<String, dynamic>))
            .toList();
        state = list;
      } catch (_) {
        // Corrupt data — start fresh.
        state = const [];
      }
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey(serial),
      jsonEncode(state.map((p) => p.toJson()).toList()),
    );
  }

  /// Add a new preset. Returns false if at max capacity.
  Future<bool> addPreset(DevicePreset preset) async {
    if (state.length >= kMaxPresets) return false;
    state = [...state, preset];
    await _persist();
    return true;
  }

  /// Remove the preset at [index].
  Future<void> removePreset(int index) async {
    if (index < 0 || index >= state.length) return;
    state = [...state]..removeAt(index);
    await _persist();
  }

  /// Replace the preset at [index] with [preset].
  Future<void> updatePreset(int index, DevicePreset preset) async {
    if (index < 0 || index >= state.length) return;
    state = [...state]..[index] = preset;
    await _persist();
  }

  /// Overwrite all presets (used by import).
  Future<void> replaceAll(List<DevicePreset> presets) async {
    state = presets.take(kMaxPresets).toList();
    await _persist();
  }
}

/// Per-device presets provider, keyed by serial number.
final devicePresetsProvider = NotifierProvider.family<DevicePresetsNotifier,
    List<DevicePreset>, String>(
  (serial) => DevicePresetsNotifier(serial),
);
