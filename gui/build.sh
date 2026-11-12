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

# Sign after the scripts are inside the bundle.
codesign --force --sign - "$ROOT/KWHotel.app"

DIST="$ROOT/dist"
STAGE="$WORK/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
ditto --norsrc "$ROOT/KWHotel.app" "$STAGE/KWHotel for MacOS.app"
codesign --force --sign - "$STAGE/KWHotel for MacOS.app"
xattr -cr "$STAGE/KWHotel for MacOS.app"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$STAGE/KWHotel for MacOS.app" "$DIST/KWHotel-for-MacOS.zip"
echo "built $OUT"
echo "package $DIST/KWHotel-for-MacOS.zip"
