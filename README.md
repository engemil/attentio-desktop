# Attentio Desktop

Attentio Desktop is a graphical user interface (GUI) for managing Attentio devices. It is built using **Flutter** for a natively compiled frontend, and **Rust** for a high-performance, safe backend core. It heavily reuses the core logic of the [`attentio-cli`](github.com/engemil/attentio-cli) tool via [`flutter_rust_bridge`](https://github.com/fzyzcjy/flutter_rust_bridge).

> **Platform support:** Linux is the primary target and is actively tested. **Windows 11** is supported but only manually tested — expect occasional rough edges. **macOS** is scaffolded by Flutter but not yet supported.

> **Connectivity (USB / BLE):** devices can be reached over **USB-CDC** (default) or **Bluetooth Low Energy**. On the overview, press **Discover** to scan for USB devices, and enable the **Bluetooth** toggle to also include BLE devices in the scan. BLE pairing/bonding is currently verified on **Linux/BlueZ** only (the first connection performs Just-Works pairing); see the [`attentio-cli`](github.com/engemil/attentio-cli) BLE notes for the underlying transport.

## Table of Contents

- [Architecture](#architecture)
- [Project layout](#project-layout)
- [Cloning](#cloning)
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
│   │   │   ├── monitor_page.dart     # Real-time two-pane serial/protocol monitor
│   │   │   └── settings_page.dart    # Appearance / Application / About
│   │   ├── widgets/                  # Reusable UI components
│   │   │   ├── app_shell.dart        # Top-level scaffold (wraps OverviewPage)
│   │   │   └── preset_edit_dialog.dart  # Preset create/edit/delete dialog
│   │   └── utils/                    # UI-specific helpers
│   │       ├── responsive.dart       # Responsive layout breakpoints
│   │       └── device_display.dart   # Canonical device display name resolver
│   ├── providers/                    # Riverpod state management
│   │   ├── devices_providers.dart    # Device list stream, per-device status, metadata, settings
│   │   ├── dfu_provider.dart         # DFU flash state (app-lifetime, survives navigation)
│   │   ├── monitor_providers.dart    # Serial (CDC0) + protocol (CDC1) monitor streams
│   │   ├── presets_provider.dart     # Per-device colour presets with SharedPreferences persistence
│   │   └── settings_provider.dart    # App settings (theme, accent, tray, autostart) persistence
│   ├── services/                     # Platform integrations and side-effect services
│   │   └── tray_service.dart         # System tray + minimize-to-tray cooperation
│   └── src/rust/                     # Auto-generated FRB bindings (gitignored)
├── rust/                             # Rust crate exposed to Flutter
│   ├── Cargo.toml
│   └── src/api/                      # Functions/structs visible to Dart
│       ├── mod.rs
│       ├── device_api.rs             # Persistent per-device ApClient cache + FFI surface
│       └── monitor_api.rs            # Serial + AP protocol monitor streams
├── rust_builder/                     # Cargokit FFI plugin glue (do not edit)
├── linux/                            # GTK runner
├── macos/, windows/                  # Scaffolded, not yet supported
├── test/                             # Unit/widget tests
└── integration_test/                 # End-to-end tests
```

## Cloning

This repo uses **git submodules** to pin the Flutter SDK (3.41.7) and the `attentio-cli` Rust backend, so a single clone gives you everything you need:

```bash
git clone --recurse-submodules https://github.com/engemil/attentio-desktop.git
```

If you already cloned without `--recurse-submodules`, initialise the submodules afterwards:

```bash
git submodule update --init --recursive
```

To pull a newer revision of `attentio-cli` (tracking its `dev` branch):

```bash
git submodule update --remote attentio-cli
git add attentio-cli && git commit -m "Bump attentio-cli submodule"
```

## VS Code Devcontainer (Recommended)

The easiest way to get started is by using the included **Devcontainer**. It builds a Linux toolchain (Rust, GTK/Wayland deps, `flutter_rust_bridge_codegen`) inside a container without modifying your host OS, and reuses the Flutter SDK from the `flutter/` submodule.

1. Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension in VS Code.
2. Open the `attentio-desktop` folder in VS Code.
3. A prompt will appear: **"Folder contains a Dev Container configuration file. Reopen folder to develop in a container."** Click **Reopen in Container**.
   - *(Alternatively, open the Command Palette (`Ctrl+Shift+P`) and run `Dev Containers: Rebuild and Reopen in Container`)*.
4. The container will build automatically. The `postCreateCommand` then initialises submodules (if needed) and runs `flutter doctor` to bootstrap the Dart SDK. Once finished, you will have `flutter`, `cargo`, and `flutter_rust_bridge_codegen` ready on your `PATH`.

The devcontainer mounts your `/dev` folder and X11/Wayland socket so the app can talk to USB devices and render its window on your host desktop. It also sets `LIBGL_ALWAYS_SOFTWARE=1` and `GDK_RENDERING=image` to avoid GLX issues with hosts running NVIDIA proprietary drivers.

## Prerequisites (Manual Setup)

If you would rather set up the toolchain on your host machine, follow the section for your OS. The Flutter SDK itself is provided by the `flutter/` submodule on both platforms (pinned to 3.41.7) — you only need to add its `bin/` directory to your `PATH`.

### Linux

1. **Rust & Cargo:**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
   source "$HOME/.cargo/env"
   ```

2. **Flutter on PATH:**
   ```bash
   export PATH="$PWD/flutter/bin:$HOME/.cargo/bin:$PATH"
   ```
   Persist across sessions by appending the line above to your `~/.bashrc` (or `~/.zshrc`) with the absolute path to your checkout.

3. **OS Dependencies:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y clang ninja-build libgtk-3-dev pkg-config libayatana-appindicator3-dev libudev-dev libusb-1.0-0-dev bluez
   ```

   > `bluez` (with a running `bluetooth` service) is required for the BLE
   > transport; USB-only use does not need it.

> Regenerating app icons is a design-time-only step and is not needed for a normal build — see [`assets/branding/README.md`](assets/branding/README.md) for the workflow and the (optional) ImageMagick dependency.

### Windows 11

Run these in **PowerShell** (the default shell on Windows 11). `winget install` will prompt for admin elevation.

1. **Rust & Cargo:**
   ```powershell
   winget install --id Rustlang.Rustup -e
   ```
   Close and reopen PowerShell so `cargo` and `rustc` land on `PATH`. The MSVC ABI is selected by default — this is what you want.

2. **Flutter on PATH** (persisted for future shells):
   ```powershell
   $flutterBin = "$PWD\flutter\bin"
   [Environment]::SetEnvironmentVariable(
       "Path",
       "$flutterBin;$env:USERPROFILE\.cargo\bin;$([Environment]::GetEnvironmentVariable('Path','User'))",
       "User")
   # …then close and reopen PowerShell, or for the current session also run:
   $env:Path = "$flutterBin;$env:USERPROFILE\.cargo\bin;$env:Path"
   ```

3. **OS Dependencies:** Visual Studio 2022 Build Tools with the **Desktop development with C++** workload (MSVC + Windows 10/11 SDK + CMake):
   ```powershell
   winget install --id Microsoft.VisualStudio.2022.BuildTools -e `
       --override "--quiet --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
   No separate libusb install is needed — `libusb1-sys` vendors and builds it from source via MSVC.

## Setup

1. Install the `flutter_rust_bridge` code generator (needed whenever the Rust API changes):
   ```bash
   cargo install flutter_rust_bridge_codegen --version 2.12.0 --locked
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

Linux:
```bash
flutter run -d linux
```

Windows:
```bash
flutter run -d windows
```

## Testing

Widget tests (fast, no hardware required):

```bash
flutter test
```

Integration tests (boots the real Rust bridge; works without a device attached — verifies either the device list or empty state renders):

Linux:
```bash
flutter test integration_test/simple_test.dart -d linux
```

Windows:
```powershell
flutter test integration_test/simple_test.dart -d windows
```

## Logging & Diagnostics

The Rust backend uses `env_logger`, controlled at runtime via `RUST_LOG`. The
default filter is `warn`, so only warnings and errors are printed.

A small number of `flutter_rust_bridge` internal warnings (e.g. `Fail to post
message to Dart`) can occasionally surface during stream teardown on app
shutdown or USB unplug. They are cosmetic. To silence them while keeping
your own backend warnings visible:

Linux:
```bash
RUST_LOG=warn,flutter_rust_bridge::rust2dart=error flutter run -d linux
```

Windows (PowerShell):
```powershell
$env:RUST_LOG = "warn,flutter_rust_bridge::rust2dart=error"
flutter run -d windows
```

To enable verbose stream-lifecycle traces (`frb_diag:` events) for debugging:

Linux:
```bash
RUST_LOG=warn,rust_lib_attentio_desktop=trace flutter run -d linux
```

Windows (PowerShell):
```powershell
$env:RUST_LOG = "warn,rust_lib_attentio_desktop=trace"
flutter run -d windows
```

## Building for Release

Linux:
```bash
flutter build linux
```
Output: `build/linux/x64/release/bundle/attentio_desktop`

Windows:
```powershell
flutter build windows
```
Output: `build\windows\x64\runner\Release\attentio_desktop.exe` (plus accompanying DLLs and `data/` folder — ship the whole `Release/` directory).

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
