#!/bin/bash
# SPDX-License-Identifier: MIT
# Remove the KWHotel Wine prefix, program files, and the Wine build this
# launcher installed. The project folder and the KWHotel installer stay.
#
#   ./uninstall.sh
#   ./uninstall.sh --yes --keep-data
#   ./uninstall.sh --yes --keep-wine

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/kwhotel.sh
source "$ROOT/lib/kwhotel.sh"

yes=0
keep_wine=0
keep_data=0

usage() {
  cat <<EOF
Usage: ./uninstall.sh [--yes] [--keep-data] [--keep-wine]

Removes:
  $WINEPREFIX
  $SUPPORT
  $CACHE
  $HOME/Desktop/KWHotel.command
  $WINE_APP

--keep-data   leave the hotel database and settings in $SUPPORT/app
--keep-wine   leave Wine Crossover installed
--yes         do not ask for confirmation

Rosetta is a macOS component and is not removed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) yes=1 ;;
    --keep-data) keep_data=1 ;;
    --keep-wine) keep_wine=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

polish=0
case "${KWHOTEL_LANG:-}${LANG:-}${LC_ALL:-}" in
  pl*|PL*) polish=1 ;;
esac

say() {
  if (( polish )); then
    printf '%s\n' "$1"
  else
    printf '%s\n' "$2"
  fi
}

refuse_dangerous() {
  case "$1" in
    ""|"/"|"$HOME"|"$HOME/")
      echo "refusing to remove ${1:-<empty>}" >&2
      exit 1
      ;;
  esac
}
refuse_dangerous "$WINEPREFIX"
refuse_dangerous "$SUPPORT"
refuse_dangerous "$CACHE"
refuse_dangerous "$WINE_APP"

if (( ! yes )); then
  if [[ ! -t 0 ]]; then
    say "Uruchom ponownie z --yes, gdy nie ma terminala." \
      "Re-run with --yes when there is no terminal." >&2
    exit 1
  fi
  say "To usunie prefiks Wine, pliki KWHotel i pamięć podręczną instalacji." \
    "This removes the Wine prefix, the KWHotel files, and the setup cache."
  if (( keep_data )); then
    say "Baza hotelu i ustawienia zostaną zachowane." \
      "The hotel database and settings will be kept."
  else
    say "Baza hotelu (KWHotel40.sdf) też zostanie usunięta. Zachowasz ją opcją --keep-data." \
      "The hotel database (KWHotel40.sdf) will be removed too. Keep it with --keep-data."
  fi
  if (( keep_wine )); then
    say "Wine Crossover zostanie na miejscu." \
      "Wine Crossover will be left in place."
  else
    say "Wine Crossover z $WINE_APP zostanie usunięte, jeśli to ta kompilacja." \
      "Wine Crossover at $WINE_APP will be removed when it is this build."
  fi
  if (( polish )); then
    printf 'Kontynuować? [y/N] '
  else
    printf 'Continue? [y/N] '
  fi
  read -r answer || exit 1
  case "$answer" in
    y|Y|yes|YES|tak|TAK) ;;
    *) exit 0 ;;
  esac
fi

if [[ -x "$WINE_BIN/wineserver" && -d "$WINEPREFIX" ]]; then
  say "Zatrzymuję KWHotel." "Stopping KWHotel."
  WINEPREFIX="$WINEPREFIX" WINEARCH=win64 "$WINE_BIN/wineserver" -k || true
  sleep 1
fi

kept=""
if (( keep_data )); then
  kept="$(mktemp -d "${TMPDIR:-/tmp}/kwhotel-keep.XXXXXX")"
  for data_file in KWHotel40.sdf KWHotel.settings KWHotel.ini Dashboard.json; do
    if [[ -f "$SUPPORT/app/$data_file" ]]; then
      cp -p "$SUPPORT/app/$data_file" "$kept/$data_file"
    fi
  done
fi

rm -rf "$WINEPREFIX" "$CACHE" "$SUPPORT"

if [[ -n "$kept" ]]; then
  if find "$kept" -type f -print -quit | grep -q .; then
    mkdir -p "$SUPPORT/app"
    cp -p "$kept"/* "$SUPPORT/app/"
    say "Baza i ustawienia zostały w $SUPPORT/app" \
      "Database and settings remain in $SUPPORT/app"
  fi
  rm -rf "$kept"
fi

desktop="$HOME/Desktop/KWHotel.command"
if [[ -f "$desktop" ]] && grep -q 'setup.sh' "$desktop"; then
  rm -f "$desktop"
fi

if (( ! keep_wine )) && [[ -d "$WINE_APP" ]]; then
  wine_version=""
  if [[ -x "$WINE_BIN/wine" ]]; then
    wine_version="$("$WINE_BIN/wine" --version 2>/dev/null || true)"
  fi
  case "$wine_version" in
    *"CrossOverFOSS 23.7.1"*)
      rm -rf "$WINE_APP"
      say "Usunięto Wine Crossover." "Removed Wine Crossover."
      ;;
    *)
      say "Zostawiam $WINE_APP, bo to nie jest Wine Crossover 23.7.1." \
        "Leaving $WINE_APP because it is not Wine Crossover 23.7.1."
      ;;
  esac
fi

say "KWHotel został odinstalowany. Folder projektu i instalator .exe zostały." \
  "KWHotel was uninstalled. The project folder and the .exe installer remain."
