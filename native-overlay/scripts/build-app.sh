#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Abar Native Overlay"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE="$ROOT_DIR/.build/release/AbarNativeOverlay"

cd "$ROOT_DIR"
swift build -c release >&2

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/AbarNativeOverlay"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>AbarNativeOverlay</string>
  <key>CFBundleIdentifier</key>
  <string>dev.abar.native-overlay</string>
  <key>CFBundleName</key>
  <string>Abar Native Overlay</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$APP_DIR" 2>/dev/null || true
/usr/bin/codesign --force --deep --sign - "$APP_DIR" >&2
echo "$APP_DIR"
