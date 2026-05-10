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

## [Development] (2026-05-10)

Fixed

- **Spurious `Fail to post message to Dart` warnings on every device action** —
  the device detail page invalidated `deviceStatusStreamProvider` after every
  claim / release / set-RGB / set-brightness / etc. action to refresh the UI
  promptly. Each invalidation tore down and respawned the underlying Rust
  streaming task, and the dropped `StreamSinkCloser` raced with Dart receive-
  port disposal, producing one warning from `flutter_rust_bridge` per action
  (visible on stderr because we install `env_logger` at `warn` level on
  Linux).

  Replaced the invalidate with a kick mechanism: a per-serial
  `tokio::sync::Notify` is awaited alongside the 2 s poll sleep via
  `tokio::select!`, and a new sync API `api_device_status_kick(serial)` calls
  `notify_one()` to wake the loop immediately. The stream task stays alive
  across the entire device-detail page session, no close-sentinel is posted,
  and status updates remain instant after each action.

  Verified end-to-end: 8 consecutive actions on a device produced 8 kick
  events and zero stream-task exits / FRB warnings.

Changed

- **`frb_diag:` lifecycle logs demoted from `debug` to `trace`** in
  `device_api.rs` and `monitor_api.rs`. They served their diagnostic purpose
  during the warning investigation; the default `RUST_LOG=warn` hides them
  either way. To re-enable for future diagnostics, run with
  `RUST_LOG=warn,rust_lib_attentio_desktop=trace`.

Added

- **`api_device_status_kick(serial)`** — sync FRB API in
  `rust/src/api/device_api.rs`. Wakes the per-serial device-status poll loop
  so it issues a fresh `get_status()` immediately rather than waiting for the
  next 2 s tick. Edge-triggered via `tokio::sync::Notify`; safe to call
  before a stream is subscribed (the first tick is immediate anyway).

---

## [Development] (2026-05-07)

Added

- **Monitor page (`lib/ui/pages/monitor_page.dart`)** — new full-screen
  two-pane view for real-time device monitoring:
  - **Protocol pane (CDC1, top):** AP command/response traffic with syntax
    colouring (outgoing → blue, OK ← green, ERROR ← red, events ← amber).
    Connection status dot, clear button, auto-scroll toggle.
  - **Serial pane (CDC0, bottom):** raw serial debug output streamed from the
    device. Same controls as the protocol pane.
  - **Log level control** in the app bar: `SegmentedButton` (ERROR / WARN /
    INFO / DEBUG) wired to `LOG_SET_LEVEL` AP command. Keyboard shortcuts
    `1`–`4` also set the level.
  - **Status bar** shows device serial, current log level, pane focus, and
    line counts.
  - **Keyboard navigation:** `Tab` toggles pane focus; `↑↓` / `PgUp/PgDn` scroll
    the focused pane; `1`–`4` change log level.

- **Monitor Rust bridge (`rust/src/api/monitor_api.rs`)** — new FFI surface
  for the desktop app:
  - `api_monitor_serial_start(serial)` — opens CDC0 and streams lines to Dart
    via `StreamSink`. Auto-reconnects on port busy / disconnect with 3 s
    backoff; uses a 1 s read timeout to detect stream cancellation promptly.
  - `api_monitor_protocol_start(serial)` — subscribes to the shared
    `ApClient` broadcast channel and streams formatted AP packets to Dart.
    Creates the `ApClient` lazily if no command has been issued yet, so the
    monitor is live as soon as the page opens.
  - `api_monitor_get_log_level(serial)` / `api_monitor_set_log_level(serial, level)` —
    runtime log level queries and changes (level 0–4).
  - `MonitorLogLevel` struct returned to Dart with `level` and `name` fields.

- **Monitor Riverpod providers (`lib/providers/monitor_providers.dart`)** —
  `serialMonitorStreamProvider(serial)` and `protocolMonitorStreamProvider(serial)`
  wrapping the FRB stream functions.

- **`slot_for` / `resolve_serial` made `pub(crate)`** in `device_api.rs` so
  `monitor_api.rs` can reach the shared `ApClient` cache and serial resolver.

Changed

- **Device Settings card restructured** — "Log Level Setting" renamed to
  "Serial Logging and Monitoring"; the monitor `IconButton` moved from the
  app bar into a new "Open Monitor" `FilledButton.icon` inside the card;
  a `Divider` + "Settings" subheading separates the button from the key-value
  settings editor below it.

- **`_DeviceSettingsCard` now takes `device: DeviceInfo`** — the card
  derives the display name internally for the `MonitorPage` navigation,
  removing the need for the caller to pass it separately.

---

## [Development] (2026-05-04)

Fixed

- **Scrollbar crash on overview page** — the `Scrollbar` widget around the
  device `ListView` had no `ScrollPosition` attached because the `ListView`
  created its own `ScrollController` while the `Scrollbar` listened to the
  `PrimaryScrollController`. Added `primary: true` to the `ListView` so both
  use the same controller.

- **Preset dialog crash at small window sizes** — the "Save as Preset" /
  "Edit Preset" `AlertDialog` contained a `Spacer` (which extends `Expanded`)
  inside the `actions` list. Flutter renders dialog actions inside an
  `OverflowBar`, which does not accept `Expanded` children. Removed the
  `Spacer` and set `actionsAlignment: MainAxisAlignment.spaceBetween` (when
  editing) to keep the Delete button on the left and Cancel/Save on the right.

- **Widget test failures** — two tests in `test/widget_test.dart` were
  checking for UI text/widgets that no longer existed:
  - "renders a card per returned device" expected `"Serial Number: SN-ABC"`
    but the overview tile now shows the device display name. Updated test
    devices to include `name` fields and asserts on those.
  - "settings button is visible" expected `find.byTooltip('Settings')` but
    the settings button had no `Tooltip`. Added a `Tooltip(message:
    'Settings')` wrapper to the settings button in the overview page.

- **Integration test stale strings** — `simple_test.dart` expected
  `"Connected Devices"` and `"No devices found…"` but the overview page
  shows `"Devices"` and `"No devices detected…"`. Updated test assertions
  to match the current UI text.

Changed

- **Generalized product references** — replaced "AL-1"-specific wording
  with generic "Attentio" / "device(s)" phrasing in the overview empty-state
  message, doc comments, and `pubspec.yaml` description.

- **Code formatting** — applied `dart format` across the codebase for
  consistent style (line wrapping, trailing commas, parameter alignment).

- **Preset grid responsiveness** — the preset grid on the device detail page
  now uses more breakpoints (3 / 4 / 5 / 6 columns) instead of a fixed
  3-or-4 split.

- **Preset tile touch targets** — increased star and edit icon sizes and
  minimum touch targets (18 px / 14 px icons with 24 px targets to 22 px /
  18 px icons with 28 px targets) for easier interaction.

- **Preset tile label style** — preset name and brightness labels changed
  from `labelSmall` to `bodySmall` for readability.

- **Detail page status header breakpoint** — raised from 640 px to 750 px
  so the stacked layout activates before content overflows.

- **Detail page identity block** — removed the lightbulb icon from the
  product silhouette head, removed `overflow: TextOverflow.ellipsis` and
  `maxLines: 1` constraints from the serial number and port info lines
  (they are now fully visible / selectable).

- **Live status block** — centred the "Live Status" title, set label text
  to `textAlign: TextAlign.right`, and wrapped value widgets in `Flexible`
  to prevent overflow.

- **FRB codegen config** — added `enable_lifetime: true` to
  `flutter_rust_bridge.yaml` to suppress the informational lifetime
  warning during code generation.

---

## [Development] (2026-05-04)

Added

- **Favourite presets on overview** — up to 6 presets per device can be marked
  as favourites (star icon on each preset tile in the detail page). Favourited
  presets appear as 32×32 coloured rounded squares inline on the overview device
  tile; tapping one immediately applies that colour and brightness to the
  device. New `isFavorite` field on `DevicePreset`, `toggleFavorite()` method,
  `kMaxFavorites` constant, and `deviceFavoritePresetsProvider` derived provider
  in `presets_provider.dart`.

- **AL-1 product silhouette swatch** — the colour swatch on both the overview
  device tiles and the device detail page header now resembles the AL-1 product
  silhouette: a coloured rectangle (light head, sharp bottom corners) with a
  wider neutral base underneath, drawn in front with a slight overlap.

- **Rounded square colour indicators** — all colour circles across the app
  (LED controls preset dots, preset tile swatches, overview favourite presets)
  have been changed to rounded squares for visual consistency.

Changed

- **Colour-dominant preset tiles** — preset tiles on the device detail page now
  fill entirely with the preset colour. Name and brightness are shown on a
  semi-transparent overlay bar at the bottom. Star and edit icons sit as small
  overlays with contrast-aware colours (light icons on dark colours, dark icons
  on light colours). Grid aspect ratio changed from 1.2 to 1.0 (square tiles).

- **Responsive overview device tiles** — device tiles use a `LayoutBuilder`
  with three breakpoints (650 / 350 px) to wrap content across 1, 2, or 3 rows
  instead of truncating text with ellipsis. The chevron stays vertically
  centred across all rows. `_FavoritePresetsRow` uses `Wrap` so many presets
  flow to additional lines. `_StatusSummary` is wrapped in `Flexible` in
  wrapped layouts to prevent overflow into the chevron.

- **Cleaner overview device tiles** — removed serial number, USB location, and
  port path info from the overview text column. Only device name and device type
  are shown (full details remain on the detail page).

- **Stable status layout** — `_StatusSummary` now has a fixed width (110 px) so
  changing brightness values (e.g. 9% → 100%) no longer shift the surrounding
  layout.

- **Status always visible** — removed the `isCompactWidth` check that hid
  `_StatusSummary` at narrow widths. Status (control mode + brightness) is now
  always shown for Normal-mode devices.

- **Compact summary cards** — the Connected / Normal / Bootloader cards now
  use smaller padding (12×8), a 24 px icon, and tighter spacing (6–8 px gaps).
  The narrow layout (< 580 px) renders as a 2×2 grid (Connected + Settings on
  top, Normal + Bootloader below) instead of a vertical stack. Card text uses
  `maxLines: 1` with ellipsis as a safety net. The settings button sizes itself
  via `AspectRatio(1)` + `IntrinsicHeight` to match card height.

- **Summary card breakpoint** raised from 520 px to 580 px so the 2×2 grid
  kicks in before card labels would wrap.

Fixed

- **Minimum window size on Linux** — `window_manager`'s `setMinimumSize` was
  silently failing on some compositors (especially Wayland) due to an
  uninitialised `window_hints` bug in v0.4.3. Added
  `gtk_widget_set_size_request(GTK_WIDGET(window), 360, 480)` in the native
  GTK runner (`linux/runner/my_application.cc`) as a reliable GTK-level
  constraint that works on both X11 and Wayland.

Dependencies

- Upgraded `window_manager` from `^0.4.3` to `^0.5.0` (fixes uninitialised
  `window_hints` flag in release builds).

---

## [Development] (2026-05-03)

Changed

- **Restructured `lib/` directory** — replaced the flat `features/` layout
  with a layer-based structure:
  - `ui/pages/` — full-screen views (`overview_page`, `device_detail_page`,
    `settings_page`).
  - `ui/widgets/` — reusable components (`app_shell`, `preset_edit_dialog`).
  - `ui/utils/` — UI-specific helpers (`responsive`, `device_display`).
  - `providers/` — all Riverpod state management (`devices_providers`,
    `presets_provider`, `settings_provider`).
  - `services/` — platform integrations (`tray_service`), unchanged.
  All `package:attentio_desktop/features/…` imports updated across source,
  widget tests, and integration tests.

Fixed

- **Integration test stale import** — `simple_test.dart` referenced a
  non-existent `dashboard_page.dart` and `DashboardPage` class. Updated to
  import `ui/pages/overview_page.dart` and assert on `OverviewPage`.

---

## [Development] (2026-05-01)

Changed

- **Cleaner overview header** — removed the "System Overview" title and
  "At-a-glance status…" subtitle text. The settings button is now a larger
  64x64 card placed on the same row as the Connected / Normal / Bootloader
  summary cards (stacks below on narrow screens).

- **Device list scrollbar** — the device list on the overview page now shows
  a persistent scrollbar indicator (`thumbVisibility: true`).

- **Device list refresh button** — added a "Refresh" button next to the
  "Devices" heading. Pressing it triggers an immediate device poll and a
  15-second fast-polling burst (2 s interval instead of the default 5 s),
  showing a spinner and countdown while active.

- **Simplified license page** — replaced Flutter's built-in multi-package
  `showLicensePage` with a custom single-page view showing only the
  application's MIT license text (monospace, selectable, no sidebar).
  Renamed "Licences" to "License" in the About section. Added `LICENSE`
  as a bundled asset.

Added

- **Device presets** — per-device colour/brightness presets stored client-side
  in `SharedPreferences`, keyed by USB serial number (max 12 per device). New
  `presets_provider.dart` (model + Riverpod family notifier) and
  `preset_edit_dialog.dart` (create / edit / delete). The `_PresetsCard` in
  the device detail page shows a grid of presets with apply, save-current,
  and export/import (JSON via `file_picker`). Import validates the serial
  number and warns on mismatch.

- **Port information** — added `serial_port` and `protocol_port` fields to
  the Rust `DeviceInfo` struct (mapped from `cdc0` / `cdc1`). Shown in
  overview device tiles and the device detail identity block.

- **Inline device rename** — edit icon next to the device name in the
  identity block opens a rename dialog. Uses a new `api_rename_device` FFI
  function that writes the setting via the cached `ApClient` and updates the
  discovery name cache (`cache_remember`) so the new name propagates
  immediately without waiting for the next poll cycle.

Changed

- **Removed Devices page** — deleted `devices_page.dart`. Overview tiles are
  now tappable and navigate directly to `DeviceDetailPage`.

- **Simplified AppShell** — stripped the adaptive drawer / rail / extended
  sidebar; `AppShell` is now a plain `Scaffold(body: OverviewPage())`.

- **Settings accessible from overview** — plain `IconButton` (gear icon) on
  the overview header row pushes `SettingsPage` as a full route with its own
  `Scaffold` + `AppBar`.

- **Renamed "Device Settings" card** — filtered out `device_name` from the
  settings list (rename is handled inline); card title changed to
  "Log Level Setting".

- **Label consistency** — "Serial Number:" everywhere (not "Serial:"),
  "Serial Data:" on overview tiles, "USB:" prefix on location.

- **Widget tests** — updated for `OverviewPage`; removed all `DevicesPage`
  references.

Dependencies

- Added `file_picker ^9.2.1`.

Fixed

- **Linux close crash (`FlutterEngineRemoveView`)** — closing the window on
  Linux triggered `FlutterEngineRemoveView` on the implicit view (which the
  embedder rejects), followed by an OpenGL cleanup assertion. Root cause:
  `window_manager`'s `close()` and `destroy()` both call `gtk_window_close()`
  internally, which always attempts to remove the implicit view. Fixed in
  `lib/services/tray_service.dart` by (1) setting `setPreventClose(true)` once
  at init so `onWindowClose` is always invoked, (2) removing the
  `setPreventClose(enabled)` toggle from `setMinimizeToTray` that was
  overriding it, and (3) using `exit(0)` to terminate the process cleanly
  when the user actually wants to quit, bypassing the GTK/Flutter teardown.

Changed

- **Replaced ink splash ripple with subtle highlight across the entire app** —
  set `splashFactory: NoSplash.splashFactory` and a primary-tinted
  `highlightColor` on both the light and dark `ThemeData` in `lib/app.dart`.
  Every button, `ListTile`, `IconButton`, `SegmentedButton`, `SwitchListTile`,
  `NavigationRail`, `DropdownButton`, and the built-in Licences page now shows
  a clean colour-change press feedback instead of the Material ripple
  animation. Removed the per-widget `Theme` / `splashColor` / `hoverColor`
  overrides that were previously applied piecemeal.

- **Colour preset dots and accent colour dots** — replaced `InkWell` with
  `GestureDetector` + `MouseRegion` in `device_detail_page.dart` and
  `settings_page.dart` for tap feedback without any splash artifact.

- **Device list cards** — replaced `GestureDetector` + `MouseRegion` with
  `InkWell` in `devices_page.dart` so tapping a device card now shows the
  subtle highlight feedback (previously had no visual feedback at all).

- **Sidebar navigation icons** — all three destinations (Overview, Devices,
  Settings) now use the filled icon variant at all times instead of switching
  between outlined (unselected) and filled (selected). Selection state is
  communicated purely through the existing colour change.

- **About section lightbulb icon** — removed the explicit
  `colorScheme.primary` tint from the app-name `ListTile` icon so it matches
  the default icon colour used by the other About entries.

Changed

- **USB VID/PID** — no desktop app code changes required; the app inherits the
  new pid.codes VID:PID (`1209:EEA1`) from the shared `attentio` CLI library.

Fixed

- **Linux build permission error** — `flutter run -d linux` failed with
  "Permission denied" when CMake tried to install the binary to `/usr/local/`.
  Fixed `linux/CMakeLists.txt` to unconditionally set `CMAKE_INSTALL_PREFIX` to
  the local bundle directory instead of only when the default was unset.

- **Missing Linux build dependency** — added `libayatana-appindicator3-dev` to
  the manual setup instructions in `README.md` and to the devcontainer
  `Dockerfile`. Required by `tray_manager` at build time.

- **Planned udev implementation** — added a "Planned Implementation(s)" section
  to `README.md` documenting the short/medium/long-term roadmap for automatic
  udev rules installation in packaged builds.

---

## [Development] (2026-04-26)

Added

- **Persistent per-device USB client cache** — `rust/src/api/device_api.rs` now
  keeps one long-lived `ApClient` per device serial behind a
  `tokio::sync::Mutex` (cached in a `OnceLock<HashMap<String, …>>`). Every FRB
  call funnels through a `with_client(serial, op)` helper that lazily opens
  the port on first use, serialises subsequent calls per device, and on a
  transport error (PortBusy / Serial / Io / Timeout / DeviceNotFound) evicts
  the bad client and retries once with a fresh open. Eliminates the self-race
  that produced spurious `PortBusy` errors when, e.g., the 2 s status poll
  and a `device_name` save overlapped.

- **Shared device display-name helper** — new
  `lib/features/devices/device_display.dart` exporting `deviceDisplayName`,
  used by Overview, Devices list, and Device detail. Priority order:
  user-assigned `device_name` → USB iProduct string → literal
  `"AttentioLight-1"`. Replaces three divergent inline fallback chains so
  every page shows the same label for the same device.

- **Adaptive sidebar / responsive layout** — new `lib/utils/responsive.dart`
  defining `kCompactWidth = 600`, `kMediumWidth = 900`, and a `NavMode`
  enum. `AppShell` now renders one of three layouts via a top-level
  `LayoutBuilder`:
    - **Drawer** (< 600 px) — hamburger in the AppBar opens a side `Drawer`
      with the destination tiles; selecting closes the drawer.
    - **Rail** (600–899 px, or user-collapsed at any width ≥ 900 px) —
      icon-and-label `NavigationRail` (76 px wide).
    - **Extended** (≥ 900 px) — full 250 px sidebar with `ListTile`s and a
      collapse toggle in the AppBar.
  A single `_kDestinations` list is the source of truth for all three modes.

- **Two new responsive widget tests** — `test/widget_test.dart` now covers
  drawer mode at 420 × 720 (hamburger opens drawer, selection closes it) and
  the manual collapse cycle at 1280 × 720 (extended ⇄ rail). Total: 5 tests.

Changed

- **Window minimum size** lowered from `400 × 300` to `360 × 480` (phone-
  portrait baseline) in `lib/main.dart`.

- **Device label everywhere** — Overview previously fell back to the literal
  `"AL-1"`, while Devices list and Device detail fell back to
  `device.deviceType ?? "AttentioLight-1"`. All four call sites now use
  `deviceDisplayName`, eliminating the `AL-1` ↔ `AttentioLight-1` flicker
  between pages.

- **Device-row layout** — across Overview, Devices list, and Device detail,
  the device-type line is now placed *between* the display name and the
  `Serial: …` line. Overview previously did not show device type at all.

- **Refresh buttons audit** — removed the redundant refresh button on the
  Devices page header and the AppBar refresh action on the Device detail
  page. Both views auto-refresh (every 5 s and 2 s respectively); the
  Settings card and Metadata card refresh icons remain (those providers do
  not auto-refresh).

- **Device detail Quick Actions** restructured:
    - **Layout:** the `Wrap`-everything block was replaced with a
      `LayoutBuilder` that renders three rows at content widths ≥ 360 px
      (`Claim` / `Release`, `Power On` / `Power Off`, `Ping` alone) and
      stacks one full-width button per row below that.
    - **Styles:** Claim, Power On, and Ping now share `FilledButton.icon`
      (primary fill); Release and Power Off use `OutlinedButton.icon`.
    - **LED Off moved out of the Controls card** and into the LED Controls
      card next to "Apply colour" (renamed from "LEDs Off" to "LED Off",
      using `OutlinedButton.icon`). Same `LayoutBuilder` pattern for narrow
      widths.

- **Overview summary cards** (`Connected` / `Normal` / `Bootloader`) now use
  a `LayoutBuilder`: stacked full-width column below 520 px, three-column
  `Row` of `Expanded`s above. Removed the inner `Expanded` from
  `_SummaryCard` so it composes correctly in either layout. The trailing
  `_StatusSummary` per device tile is hidden at compact widths.

- **Theme segmented button** — removed the per-segment icons from
  `_ThemeModeTile` (`System` / `Light` / `Dark`) so the labels no longer
  wrap to two lines (`Syste`/`m`) when the wide-layout `Flexible` constrains
  the control's width.

- **Existing AppShell test** pinned to a `1280 × 720` surface to keep it
  exercising the canonical extended-sidebar layout regardless of harness
  defaults.

Fixed

- **Theme segmented button label wrapping** — selecting System / Light /
  Dark in Settings → Appearance caused the active segment's label to wrap
  onto two lines. The Material 3 `SegmentedButton` was injecting a check
  icon into the selected segment, widening it inside the wide-layout
  `Flexible` wrapper and squeezing the label. Fixed in
  `lib/features/settings/settings_page.dart` by setting
  `showSelectedIcon: false` and `softWrap: false` on each segment label.

- **Spurious `PortBusy` on writes** — saving `device_name` (or any other
  setting) while the detail page was actively polling status produced a
  `port /dev/ttyACM* is busy` error. Root cause was the GUI racing itself:
  every FRB call independently opened the port with `TIOCEXCL`, so two
  concurrent calls in the same process collided. Fixed by the persistent
  per-device client cache (above).

- **Transient device-name flicker** (companion to the CLI cache) — the
  display helper transparently benefits from `attentio`'s last-known-name
  cache, so a momentary failed read no longer flips the label to a fallback
  for one render cycle.

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
