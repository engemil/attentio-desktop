#!/usr/bin/env bash
# Regenerate every platform icon from assets/branding/app_icon_master.png.
#
# Usage: from the repo root, run:
#   ./assets/branding/regenerate-icons.sh
#
# Requirements (on Linux):
#   sudo apt install -y imagemagick
#
# The master is expected to be a 1024×1024 PNG. All outputs are deterministic
# resizes / re-encodes of that master, so re-running is safe.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

MASTER="assets/branding/app_icon_master.png"

if [[ ! -f "$MASTER" ]]; then
  echo "ERROR: $MASTER not found." >&2
  echo "Place a 1024×1024 PNG at that path and re-run." >&2
  exit 1
fi

if ! command -v convert >/dev/null 2>&1; then
  echo "ERROR: ImageMagick not installed." >&2
  echo "Install with: sudo apt install -y imagemagick" >&2
  exit 1
fi

# Master sanity check — ImageMagick prints "WxH" via -format
dims=$(identify -format "%wx%h" "$MASTER")
if [[ "$dims" != "1024x1024" ]]; then
  echo "WARNING: $MASTER is $dims, expected 1024x1024. Proceeding anyway." >&2
fi

echo "→ Generating per-size PNGs in assets/branding/"
for sz in 16 22 24 32 48 64 96 128 256 512 1024; do
  convert "$MASTER" -resize ${sz}x${sz} "assets/branding/app_icon_${sz}.png"
done

echo "→ Updating runtime assets (window_manager + tray_manager)"
cp assets/branding/app_icon_256.png assets/branding/app_icon.png
cp assets/branding/app_icon_256.png linux/runner/resources/app_icon.png

echo "→ Building Windows multi-size .ico"
convert \
  assets/branding/app_icon_16.png \
  assets/branding/app_icon_24.png \
  assets/branding/app_icon_32.png \
  assets/branding/app_icon_48.png \
  assets/branding/app_icon_64.png \
  assets/branding/app_icon_128.png \
  assets/branding/app_icon_256.png \
  windows/runner/resources/app_icon.ico

echo "→ Replacing macOS AppIcon set"
for sz in 16 32 64 128 256 512 1024; do
  cp "assets/branding/app_icon_${sz}.png" \
     "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${sz}.png"
done

echo "→ Replacing Linux hicolor theme icons"
for sz in 16 32 48 64 128 256 512; do
  mkdir -p "linux/hicolor/${sz}x${sz}/apps"
  cp "assets/branding/app_icon_${sz}.png" \
     "linux/hicolor/${sz}x${sz}/apps/com.example.attentio_desktop.png"
done

echo
echo "Done. Next steps:"
echo "  flutter clean && flutter run -d linux    # verify tray + window icon"
echo
echo "On Linux, also reinstall the system-wide icons so the launcher / dock"
echo "pick up the new artwork:"
echo "  cp linux/com.example.attentio_desktop.desktop ~/.local/share/applications/"
echo "  for sz in 16 32 48 64 128 256 512; do"
echo "    mkdir -p ~/.local/share/icons/hicolor/\${sz}x\${sz}/apps"
echo "    cp linux/hicolor/\${sz}x\${sz}/apps/com.example.attentio_desktop.png \\"
echo "       ~/.local/share/icons/hicolor/\${sz}x\${sz}/apps/"
echo "  done"
echo "  gtk-update-icon-cache ~/.local/share/icons/hicolor/"
