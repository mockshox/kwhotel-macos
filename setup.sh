#!/bin/bash
# SPDX-License-Identifier: MIT
# Install KWHotel on an Apple Silicon or Intel Mac without a Windows VM.
#
# From this folder, on a new computer:
#   xattr -dr com.apple.quarantine .
#   ./setup.sh --launch
#
# Put the Windows installer at installer/KWHotel*.exe before copying this
# folder to another Mac. Later launches can use KWHotel.app.
#
# Safe to run again. Wine, the prefix, and .NET Framework are left in place
# when they are already the expected versions.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/kwhotel.sh
source "$ROOT/lib/kwhotel.sh"

usage() {
  cat <<EOF
Usage: ./setup.sh [--launch]

Installs Wine Crossover 23.7.1, Rosetta on Apple Silicon, a private Wine
prefix, .NET Framework 4.8, and KWHotel.

The KWHotel installer must be at:
  $ROOT/installer/KWHotel*.exe

An existing $HOME/KWHotel/KWHotel.exe is used when the installer is absent.
EOF
}

launch=0
case "${1:-}" in
  "" ) ;;
  --launch) launch=1 ;;
  -h|--help) usage; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

setup_all
if (( launch )); then
  launch_kwhotel
fi
