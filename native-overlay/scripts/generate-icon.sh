#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_ICON="$ROOT_DIR/../docs/images/abar-icon.png"
OUTPUT_DIR="$ROOT_DIR/.build/abar-icon"
ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"
OUTPUT_ICON="$OUTPUT_DIR/AppIcon.icns"

if [[ ! -f "$SOURCE_ICON" ]]; then
  echo "缺少应用图标源文件：$SOURCE_ICON" >&2
  exit 1
fi

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

make_icon() {
  local pixels="$1"
  local filename="$2"
  /usr/bin/sips -z "$pixels" "$pixels" "$SOURCE_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICON"
echo "$OUTPUT_ICON"
