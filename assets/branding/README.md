# App icon assets

Every platform icon used by Attentio Desktop is generated from a single
master image in this folder:

- `app_icon_master.png` — 1024×1024 PNG, the canonical source.
- `app_icon_master.svg` — vector source (Inkscape-friendly), kept for
  future edits.

The committed Windows `.ico`, macOS `AppIcon.appiconset/`, Linux `hicolor`
PNGs, the GTK runner PNG, and the Flutter runtime asset
(`app_icon.png`) are all rebuilt from the master by
`regenerate-icons.sh` in this folder.

## To replace the icon

1. Design a new icon. Recommended: vector in Inkscape, then export a
   1024×1024 PNG. Any 1024×1024 PNG works (GIMP, Krita, Figma,
   AI-generated, etc.). Design constraints worth respecting:
   - Square, exactly 1024×1024 px.
   - Recognisable at 16 px — avoid fine detail and small text.
   - ~10% padding from the canvas edge — macOS clips the icon to a
     rounded mask, and the dock/tray reserve some breathing room.
   - 2–3 colours, high contrast.

2. Overwrite the master:
   ```bash
   cp /path/to/your-icon.png assets/branding/app_icon_master.png
   ```

3. Run the regeneration script (requires `imagemagick`):
   ```bash
   ./assets/branding/regenerate-icons.sh
   ```
   This rebuilds every per-size PNG, the Windows multi-size `.ico`, the
   macOS AppIcon set, the Linux hicolor tree, and the Flutter runtime
   asset.

4. Verify:
   ```bash
   flutter clean && flutter run -d linux
   ```
   The new icon should show in the window title bar, taskbar, and (after
   enabling Minimize-to-tray in Settings) the system tray.

5. On Linux, also reinstall the system-wide icons so the application
   launcher uses the new artwork — the script prints these commands
   when it finishes.

## Installing ImageMagick

- Linux: `sudo apt-get install -y imagemagick`
- macOS: `brew install imagemagick`
- Windows: `winget install ImageMagick.ImageMagick`

The devcontainer (`.devcontainer/Dockerfile`) already installs it, so no
extra step is needed when developing inside the container.
