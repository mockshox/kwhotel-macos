#!/bin/bash
# SPDX-License-Identifier: MIT
# Install KWHotel on an Apple Silicon or Intel Mac without a Windows VM.
#
# On a new computer, double-click KWHotel.app and choose KWHotel*.exe.
# The same install from Terminal:
#   xattr -dr com.apple.quarantine KWHotel.app
#   ./setup.sh --launch
#
# The window passes the chosen installer as KWHOTEL_INSTALLER. A file at
# installer/KWHotel*.exe is used when that variable is unset.
#
# Safe to run again. Wine, the prefix, and .NET Framework are left in place
# when they are already the expected versions.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/kwhotel.sh
source "$ROOT/lib/kwhotel.sh"

usage() {
  cat <<EOF
Usage: ./setup.sh [--launch | --launch-only]

Installs Wine Crossover 23.7.1, Rosetta on Apple Silicon, a private Wine
prefix, .NET Framework 4.8, and KWHotel. --launch also starts KWHotel.
--launch-only starts KWHotel when it is already installed.

Choose the KWHotel installer in KWHotel.app, pass it as KWHOTEL_INSTALLER,
or put it at:
  $ROOT/installer/KWHotel*.exe

An existing $HOME/KWHotel/KWHotel.exe is used when the installer is absent.
EOF
}

launch=0
launch_only=0
case "${1:-}" in
  "" ) ;;
  --launch) launch=1 ;;
  --launch-only) launch_only=1 ;;
  -h|--help) usage; exit 0 ;;
  *) die "unknown argument: $1" ;;
esac

if (( launch_only )); then
  launch_kwhotel
  exit 0
fi

setup_all
if (( launch )); then
  launch_kwhotel
fi
