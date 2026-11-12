#!/bin/bash
# SPDX-License-Identifier: MIT
# Rebuild the graphical installer inside KWHotel.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/gui/main.swift"
OUT="$ROOT/KWHotel.app/Contents/MacOS/KWHotel"
WORK="$ROOT/.cache/gui-build"
mkdir -p "$WORK" "$(dirname "$OUT")"

swiftc -swift-version 5 -O -target arm64-apple-macosx12.0 -o "$WORK/KWHotel-arm64" "$SRC"
if swiftc -swift-version 5 -O -target x86_64-apple-macosx12.0 -o "$WORK/KWHotel-x64" "$SRC"; then
  lipo -create -output "$WORK/KWHotel" "$WORK/KWHotel-arm64" "$WORK/KWHotel-x64"
elif [[ "${KWHOTEL_REQUIRE_UNIVERSAL:-}" == 1 ]]; then
  echo "x86_64 SDK unavailable; a customer build must include Intel and Apple Silicon" >&2
  exit 1
else
  echo "x86_64 SDK unavailable; writing an arm64-only app" >&2
  cp "$WORK/KWHotel-arm64" "$WORK/KWHotel"
fi
chmod +x "$WORK/KWHotel"
# Replace the directory entry so a running installer keeps its old inode.
mv -f "$WORK/KWHotel" "$OUT"

RES="$ROOT/KWHotel.app/Contents/Resources"
mkdir -p "$RES/lib"
cp "$ROOT/setup.sh" "$ROOT/uninstall.sh" "$RES/"
cp "$ROOT/lib/kwhotel.sh" "$RES/lib/kwhotel.sh"
cp "$ROOT/assets/logo.jpg" "$RES/logo.jpg"
chmod +x "$RES/setup.sh" "$RES/uninstall.sh"

swiftc -O -o "$WORK/make-icon" "$ROOT/gui/make-icon.swift"
"$WORK/make-icon" "$ROOT/assets/logo.jpg" "$WORK/icon-1024.png"
ICONSET="$WORK/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$ICONSET" "$RES/AppIcon.icns" <<'PY'
import struct, sys
from pathlib import Path
iconset, dest = Path(sys.argv[1]), Path(sys.argv[2])
chunks = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png"),
]
body = b""
for kind, name in chunks:
    data = (iconset / name).read_bytes()
    body += kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data
dest.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)
PY

# Sign after the scripts and icon are inside the bundle.
codesign --force --sign - "$ROOT/KWHotel.app"

DIST="$ROOT/dist"
STAGE="$WORK/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto --norsrc "$ROOT/KWHotel.app" "$STAGE/KWHotel for MacOS.app"
cp "$ROOT/open-on-mac.txt" "$STAGE/Open on Mac.txt"
codesign --force --sign - "$STAGE/KWHotel for MacOS.app"
xattr -cr "$STAGE"
(
  cd "$STAGE"
  COPYFILE_DISABLE=1 ditto -c -k --norsrc . "$DIST/KWHotel-for-MacOS.zip"
)
mkdir -p "$ROOT/download"
cp "$DIST/KWHotel-for-MacOS.zip" "$ROOT/download/KWHotel-for-MacOS.zip"
echo "built $OUT"
echo "package $ROOT/download/KWHotel-for-MacOS.zip"
