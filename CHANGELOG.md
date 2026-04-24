# Changelog

All notable changes to the Attentio Desktop (`attentio-desktop`) application
will be documented in this file.

**Version Format:** MAJOR.MINOR.PATCH
- **MAJOR:** Incompatible UX or behaviour changes
- **MINOR:** New features (backward compatible)
- **PATCH:** Bug fixes (backward compatible)

[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Note: Update `pubspec.yaml` when publishing a new version.

---

## [Development] (2026-04-24)

Added

- **Overview page** — new top-level landing page replacing the old Dashboard.
  Shows an at-a-glance summary of every connected AL-1: summary stat cards
  (total connected, Normal-mode, Bootloader-mode) plus per-device rows with
  a live colour swatch, name, serial, mode badge, control mode, and
  brightness. Read-only; auto-refreshes every 5 seconds.

- **Devices page** — dedicated list view of every connected AL-1 (live
  colour swatch, name, serial, device type, mode chip). Clicking a card
  navigates to a full-screen detail page. Auto-refreshes every 5 seconds.

- **Device detail page** — per-device control panel with:
  - Header card (live colour swatch, name, serial, USB location).
  - LED controls: preset colour dots, RGB sliders, hex preview, "Apply
    colour" (uses `apiSetRgb`), brightness slider and "Apply brightness"
    (uses `apiSetBrightness`), and "LEDs Off" (uses `apiLedOff`).
  - Power & session card: Power On/Off, Claim, Release, Ping.
  - Live status card with human-readable system state, control mode,
    active controller, standalone mode, colour, brightness, and session
    ID (auto-refreshes every 2 s).
  - Collapsible Metadata section.
  - Collapsible, editable Device Settings section (per-key Save buttons).

- **Settings page** — replaced the previous stub with a full implementation
  organised into three Material 3 sections:
  - **Appearance:** theme mode (System / Light / Dark segmented button),
    accent colour picker (9-colour palette, seeds `ColorScheme.fromSeed`),
    language dropdown (English only, extension point for future locales).
  - **Application:** "Minimize to system tray on close" switch, "Autostart
    on login" switch.
  - **About:** app icon, name, version (from `package_info_plus`), source
    code link, licences viewer.

- **App settings persistence** — new `AppSettingsNotifier` (Riverpod
  `Notifier<AppSettings>`) backed by `shared_preferences`. Settings are
  loaded at launch and persisted on every change.

- **Theme wiring** — `AttentioApp` is now a `ConsumerWidget` that watches
  `appSettingsProvider` and derives light/dark `ThemeData` via
  `ColorScheme.fromSeed(accentColor)`. Changes take effect instantly.

- **System tray integration (`TrayService`)** — singleton service that
  cooperates with `WindowManager` + `TrayManager`. When "minimize to tray
  on close" is enabled, closing the window hides it and installs a tray
  icon with "Show Attentio Desktop" and "Quit" menu items. Disabling the
  setting tears the tray down and restores normal close behaviour.

- **Autostart integration** — wired up via `launch_at_startup`. Toggle in
  Settings enables/disables login-time autostart on Linux/macOS/Windows.

- **Periodic device polling** — new `devicesStreamProvider` (5 s interval)
  and `deviceStatusStreamProvider.family<String>` (2 s interval) replace
  the old one-shot `FutureProvider`s for always-fresh device data.

- **Expanded Rust FFI surface (`rust/src/api/device_api.rs`)** — bindings
  for the full AP protocol client:
  - `api_list_devices_full` — returns `DeviceInfo` (serial, name, device
    type, mode, USB location) instead of just serials.
  - `api_claim`, `api_release`, `api_ping` — session control.
  - `api_set_rgb`, `api_set_hsv`, `api_set_brightness`, `api_led_off` —
    LED control (auto-claims before each call).
  - `api_power_on`, `api_power_off` — power control.
  - `api_get_metadata`, `api_settings_list`, `api_settings_get`,
    `api_settings_set` — metadata and persistent device settings.
  - `DeviceInfo` and `KvEntry` FRB structs added alongside the existing
    `DeviceStatus` mirror.

Changed

- **Navigation restructure** — sidebar now has three entries:
  - **Overview** (was "Dashboard"; repurposed into a read-only summary).
  - **Devices** (new; contains the connected-device list that used to live
    on the Dashboard).
  - **Settings** (unchanged position; now fully implemented).
  - `AppSection.dashboard` renamed to `AppSection.overview`, added
    `AppSection.devices`.

- **`main.dart` initialisation** — now calls
  `WindowManager.ensureInitialized()` and `TrayService.instance.init()`
  on desktop platforms so the minimize-to-tray and autostart settings can
  take effect.

- **Widget tests (`test/widget_test.dart`)** — rewritten to match the new
  page structure (Devices page empty state, device list rendering, and
  Overview/Devices/Settings sidebar navigation). All 3 tests pass.

Removed

- **Old `DashboardPage`** (`lib/features/dashboard/`) — superseded by the
  Overview + Devices split.
- **`DeviceCard` widget** (`lib/widgets/device_card.dart`) — the overview
  and devices pages now render their own inline cards tailored to each
  page's role.
- **Status dialog** — replaced by the full-screen Device detail page.

Dependencies

- Added `shared_preferences ^2.3.2`, `tray_manager ^0.5.0`,
  `launch_at_startup ^0.5.1`, `window_manager ^0.4.3`,
  `package_info_plus ^8.3.1`, and `url_launcher ^6.3.2`.

Notes

- **Linux system dependency:** `tray_manager` requires the
  `libayatana-appindicator3-dev` (or `appindicator3-0.1`) package at build
  time. Install with `sudo apt-get install libayatana-appindicator3-dev`
  on Debian/Ubuntu.
