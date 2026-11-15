#!/bin/bash
# Turns a square PNG (ideally 1024×1024) into AppIcon.icns with the macOS built-in sips and iconutil.
# Usage: bash make-icon.sh ~/Downloads/icon.png   → then: bash build.sh
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: bash make-icon.sh path/to/icon.png" >&2; exit 1; }
src="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")"

work="$(mktemp -d)"
set="$work/AppIcon.iconset"
mkdir -p "$set"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$src" --out "$set/icon_${size}x${size}.png" >/dev/null
    sips -s format png -z $((size * 2)) $((size * 2)) "$src" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o AppIcon.icns
rm -rf "$work"
echo "AppIcon.icns is ready. Now run: bash build.sh"
