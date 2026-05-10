# Attentio Desktop

Attentio Desktop is a graphical user interface (GUI) for managing Attentio devices. It is built using **Flutter** for a natively compiled frontend, and **Rust** for a high-performance, safe backend core. It heavily reuses the core logic of the [`attentio-cli`](github.com/engemil/attentio-cli) tool via [`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge).

> **Platform support:** Linux is the primary target and is actively tested. The `macos/` and `windows/` folders are scaffolded by Flutter but are **not yet officially supported** — expect rough edges if you try them.

## Table of Contents

- [Architecture](#architecture)
- [Project layout](#project-layout)
- [VS Code Devcontainer (Recommended)](#vs-code-devcontainer-recommended)
- [Prerequisites (Manual Setup)](#prerequisites-manual-setup)
- [Setup](#setup)
- [Development](#development)
- [Testing](#testing)
- [Logging & Diagnostics](#logging--diagnostics)
- [Building for Release](#building-for-release)
- [License](#license)


## Architecture

- **Frontend:** Flutter (Dart) with `flutter_riverpod` for state management.
- **Backend:** Rust (compiles to a native library dynamically loaded by Flutter).
- **Bridge:** `flutter_rust_bridge_codegen` generates Dart bindings for the Rust API in `rust/src/api/`.

## Project layout

```
attentio-desktop/
├── lib/                              # Flutter / Dart application
│   ├── main.dart                     # Entry point (RustLib.init, window/tray setup, runApp)
│   ├── app.dart                      # MaterialApp wrapper + Riverpod-driven theme
│   ├── ui/                           # All visual / presentation code
│   │   ├── pages/                    # Full-screen views
│   │   │   ├── overview_page.dart    # Landing page: summary cards + tappable device tiles
│   │   │   ├── device_detail_page.dart  # Per-device control panel
│   │   │   └── settings_page.dart    # Appearance / Application / About
│   │   ├── widgets/                  # Reusable UI components
│   │   │   ├── app_shell.dart        # Top-level scaffold (wraps OverviewPage)
│   │   │   └── preset_edit_dialog.dart  # Preset create/edit/delete dialog
│   │   └── utils/                    # UI-specific helpers
│   │       ├── responsive.dart       # Responsive layout breakpoints
│   │       └── device_display.dart   # Canonical device display name resolver
│   ├── providers/                    # Riverpod state management
│   │   ├── devices_providers.dart    # Device list stream, per-device status, metadata, settings
│   │   ├── presets_provider.dart     # Per-device colour presets with SharedPreferences persistence
│   │   └── settings_provider.dart    # App settings (theme, accent, tray, autostart) persistence
│   ├── services/                     # Platform integrations and side-effect services
│   │   └── tray_service.dart         # System tray + minimize-to-tray cooperation
│   └── src/rust/                     # Auto-generated FRB bindings (gitignored)
├── rust/                             # Rust crate exposed to Flutter
│   ├── Cargo.toml
│   └── src/api/                      # Functions/structs visible to Dart
│       ├── mod.rs
│       └── device_api.rs             # Persistent per-device ApClient cache + FFI surface
├── rust_builder/                     # Cargokit FFI plugin glue (do not edit)
├── linux/                            # GTK runner
├── macos/, windows/                  # Scaffolded, not yet supported
├── test/                             # Unit/widget tests
└── integration_test/                 # End-to-end tests
```

## VS Code Devcontainer (Recommended)

The easiest way to get started is by using the included **Devcontainer**. It automatically sets up Flutter (pinned version), Rust, and all required Linux GTK/Wayland GUI dependencies inside a container without modifying your host OS.

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension in VS Code.
2. Open the `attentio-desktop` folder in VS Code.
3. A prompt will appear: **"Folder contains a Dev Container configuration file. Reopen folder to develop in a container."** Click **Reopen in Container**.
   - *(Alternatively, open the Command Palette (`Ctrl+Shift+P`) and run `Dev Containers: Rebuild and Reopen in Container`)*.
4. The container will build automatically. Once finished, you will have `flutter`, `cargo`, and `flutter_rust_bridge_codegen` ready on your `PATH`.

The devcontainer mounts your `/dev` folder and X11/Wayland socket so the app can talk to USB devices and render its window on your host desktop. It also sets `LIBGL_ALWAYS_SOFTWARE=1` and `GDK_RENDERING=image` to avoid GLX issues with hosts running NVIDIA proprietary drivers.

## Prerequisites (Manual Setup)

If you would rather set up the toolchain on your host machine:

1. **Rust & Cargo:**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
   source "$HOME/.cargo/env"
   ```

2. **Flutter SDK (pinned to 3.41.7):**
   ```bash
   git clone --depth 1 --branch 3.41.7 https://github.com/flutter/flutter.git ~/flutter
   export PATH="$HOME/flutter/bin:$PATH"
   ```
   Add the following to your `~/.bashrc` (or `~/.zshrc`) to persist across sessions:
   ```bash
   export PATH="$HOME/.cargo/bin:$HOME/flutter/bin:$PATH"
   ```

3. **Linux OS Dependencies:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y clang ninja-build libgtk-3-dev pkg-config libayatana-appindicator3-dev libudev-dev libusb-1.0-0-dev
   ```

## Setup

1. Install the `flutter_rust_bridge` code generator (needed whenever the Rust API changes):
   ```bash
   cargo install flutter_rust_bridge_codegen
   ```
2. Fetch Flutter dependencies:
   ```bash
   flutter pub get
   ```

## Development

> **Note:** If switching between the devcontainer and a manual (host) setup,
> or if you encounter stale build cache errors, run a full clean first:
> ```bash
> flutter clean
> rm -rf build/ rust/target/
> flutter pub get
> ```

If you modify the Rust code under `rust/src/api/`, regenerate the Dart bindings before running:

```bash
flutter_rust_bridge_codegen generate
```

Run the app in debug mode (hot-reload enabled):

```bash
flutter run -d linux
```

## Testing

Widget tests (fast, no hardware required):

```bash
flutter test
```

Integration tests (boots the real Rust bridge; works without a device attached — verifies either the device list or empty state renders):

```bash
flutter test integration_test/simple_test.dart -d linux
```

## Logging & Diagnostics

The Rust backend uses `env_logger`, controlled at runtime via `RUST_LOG`. The
default filter is `warn`, so only warnings and errors are printed.

A small number of `flutter_rust_bridge` internal warnings (e.g. `Fail to post
message to Dart`) can occasionally surface during stream teardown on app
shutdown or USB unplug. They are cosmetic. To silence them while keeping
your own backend warnings visible:

```bash
RUST_LOG=warn,flutter_rust_bridge::rust2dart=error flutter run -d linux
```

To enable verbose stream-lifecycle traces (`frb_diag:` events) for debugging:

```bash
RUST_LOG=warn,rust_lib_attentio_desktop=trace flutter run -d linux
```

## Building for Release

```bash
flutter build linux
```

The optimised binary and its assets will be at:
`build/linux/x64/release/bundle/attentio_desktop`

## License

MIT License, see `LICENSE` for details. For submodule licenses, see the individual repository `LICENSE` files.

## Planned Implementation(s)

### Linux USB Permissions (udev Rules)

The desktop app requires udev rules on Linux to access Attentio USB devices without root privileges. This is currently a manual step and needs proper integration as the project matures.

**Short-term (current):**
Users must manually run the udev rules script from the CLI tool or firmware repository:
```bash
sudo ./scripts/udev_rules_attentio.sh   # from attentio-cli or attentiolight-1-firmware repo
```
This installs rules for the Attentio VID:PID (`1209:eea1`) and the STM32 DFU fallback (`0483:df11`).

**Medium-term (with packaging):**
When a distribution package is created (`.deb`, AppImage, Flatpak, etc.), udev rules should be installed automatically:
- **`.deb` package:** Include udev rules via `debian/attentio-desktop.udev` or a `postinst` script that copies the `.rules` file to `/etc/udev/rules.d/`.
- **AppImage:** Bundle the `.rules` file inside the image and document a manual copy step (AppImages are read-only and cannot write to `/etc/`).
- **Flatpak:** Document manual udev setup (Flatpak is sandboxed and cannot write system files).

**Long-term (in-app UX):**
Add a USB permissions health check in the desktop app UI:
- On startup or device discovery failure, detect if the device cannot be opened due to missing permissions.
- Show a dialog with clear instructions, and optionally a "Fix permissions" button that uses `pkexec` to install the udev rules via a bundled helper script.
