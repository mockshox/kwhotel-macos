# SPDX-License-Identifier: MIT
# Shared paths and installers for the KWHotel macOS launcher.
# Sourced by setup.sh and KWHotel.app. Requires ROOT and bash 3.2.

SUPPORT="${KWHOTEL_SUPPORT:-$HOME/Library/Application Support/KWHotel}"
CACHE="${KWHOTEL_CACHE:-$HOME/Library/Caches/kwhotel-setup}"
WINE_APP="${KWHOTEL_WINE_APP:-$HOME/Applications/Wine Crossover.app}"
WINE_BIN="$WINE_APP/Contents/Resources/wine/bin"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine-kwhotel}"
LOG="$SUPPORT/setup.log"
STAMP="$SUPPORT/install-stamp"

WINE_VERSION="23.7.1-1"
WINE_URL="https://github.com/jfuruness/wine-crossover-mac/releases/download/${WINE_VERSION}/wine-crossover-${WINE_VERSION}-osx64.tar.xz"
WINE_SHA256="e24ba084737c8823e8439f7cb75d436a917fd92fc34b832bcaa0c0037eb33d03"

SEVENZIP_URL="https://www.7-zip.org/a/7z2501-mac.tar.xz"
SEVENZIP_SHA256="26aa75bc262bb10bf0805617b95569c3035c2c590a99f7db55c7e9607b2685e0"

WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/20260125/src/winetricks"
WINETRICKS_SHA256="431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

CABEXTRACT_URL="https://cabextract.org.uk/cabextract-1.11.tar.gz"
CABEXTRACT_SHA256="b5546db1155e4c718ff3d4b278573604f30dd64c3c5bfd4657cd089b823a3ac6"

DOTNET_RELEASE_MIN=528040

log() {
  printf '%s\n' "$*" >&2
  if [[ -n "${LOG:-}" ]]; then
    mkdir -p "$(dirname "$LOG")"
    printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >>"$LOG"
  fi
}

die() {
  log "error: $*"
  exit 1
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

download() {
  local url="$1" dest="$2" sha="$3"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]] && [[ "$(sha256_file "$dest")" == "$sha" ]]; then
    return 0
  fi
  log "downloading $(basename "$dest")"
  curl -fL --retry 3 --retry-delay 2 -o "$dest.partial" "$url"
  local got
  got="$(sha256_file "$dest.partial")"
  if [[ "$got" != "$sha" ]]; then
    rm -f "$dest.partial"
    die "checksum mismatch for $(basename "$dest")"
  fi
  mv "$dest.partial" "$dest"
}

ensure_rosetta() {
  if [[ "$(uname -m)" != "arm64" ]]; then
    return 0
  fi
  if arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    return 0
  fi
  log "installing Rosetta"
  softwareupdate --install-rosetta --agree-to-license
  arch -x86_64 /usr/bin/true >/dev/null 2>&1 || die "Rosetta did not install"
}

ensure_cabextract() {
  if command -v cabextract >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$CACHE/bin"
  if [[ -x "$CACHE/bin/cabextract" ]]; then
    export PATH="$CACHE/bin:$PATH"
    return 0
  fi
  if command -v brew >/dev/null 2>&1; then
    log "installing cabextract with Homebrew"
    brew install cabextract
    return 0
  fi
  command -v clang >/dev/null 2>&1 || die "cabextract is missing and there is no clang to build it. Install Xcode Command Line Tools or Homebrew, then run setup again."
  local tarball="$CACHE/cabextract-1.11.tar.gz"
  download "$CABEXTRACT_URL" "$tarball" "$CABEXTRACT_SHA256"
  log "building cabextract"
  rm -rf "$CACHE/cabextract-1.11"
  tar -xzf "$tarball" -C "$CACHE"
  (
    cd "$CACHE/cabextract-1.11"
    ./configure --prefix="$CACHE/cabextract-prefix"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
  ln -sfn "$CACHE/cabextract-prefix/bin/cabextract" "$CACHE/bin/cabextract"
  export PATH="$CACHE/bin:$PATH"
  command -v cabextract >/dev/null 2>&1 || die "cabextract build failed"
}

ensure_7zz() {
  if command -v 7zz >/dev/null 2>&1; then
    return 0
  fi
  if command -v 7z >/dev/null 2>&1; then
    mkdir -p "$CACHE/bin"
    ln -sfn "$(command -v 7z)" "$CACHE/bin/7zz"
    export PATH="$CACHE/bin:$PATH"
    return 0
  fi
  local archive="$CACHE/7z2501-mac.tar.xz"
  download "$SEVENZIP_URL" "$archive" "$SEVENZIP_SHA256"
  mkdir -p "$CACHE/bin"
  tar -xJf "$archive" -C "$CACHE/bin" 7zz
  chmod +x "$CACHE/bin/7zz"
  xattr -dr com.apple.quarantine "$CACHE/bin/7zz" 2>/dev/null || true
  export PATH="$CACHE/bin:$PATH"
}

ensure_winetricks() {
  local dest="$CACHE/bin/winetricks"
  download "$WINETRICKS_URL" "$dest" "$WINETRICKS_SHA256"
  chmod +x "$dest"
  export PATH="$CACHE/bin:$PATH"
}

ensure_wine() {
  if [[ -x "$WINE_BIN/wine" ]]; then
    local ver
    ver="$("$WINE_BIN/wine" --version 2>/dev/null || true)"
    if [[ "$ver" == *"CrossOverFOSS 23.7.1"* ]]; then
      export PATH="$WINE_BIN:$PATH"
      return 0
    fi
    log "replacing unexpected Wine ($ver)"
  fi
  local archive="$CACHE/wine-crossover-${WINE_VERSION}-osx64.tar.xz"
  download "$WINE_URL" "$archive" "$WINE_SHA256"
  log "installing Wine Crossover into $WINE_APP"
  mkdir -p "$(dirname "$WINE_APP")"
  rm -rf "$WINE_APP"
  tar -xJf "$archive" -C "$(dirname "$WINE_APP")"
  xattr -dr com.apple.quarantine "$WINE_APP" 2>/dev/null || true
  codesign --force --deep -s - "$WINE_APP"
  [[ -x "$WINE_BIN/wine" ]] || die "Wine Crossover did not install"
  export PATH="$WINE_BIN:$PATH"
}

wine_env() {
  export PATH="$WINE_BIN:$CACHE/bin:$PATH"
  export WINEPREFIX
  export WINEARCH=win64
  export WINEDEBUG="${WINEDEBUG:--all}"
  export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-quartz=n}"
}

ensure_prefix() {
  wine_env
  if [[ -f "$WINEPREFIX/system.reg" ]]; then
    return 0
  fi
  log "creating Wine prefix $WINEPREFIX"
  wineboot --init
}

dotnet_release() {
  wine_env
  local line hex
  line="$(wine reg query 'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' /v Release 2>/dev/null | awk '/Release/{print $NF}' | tr -d '\r' || true)"
  if [[ -z "$line" ]]; then
    echo 0
    return 0
  fi
  echo $((line))
}

ensure_dotnet() {
  wine_env
  local release
  release="$(dotnet_release)"
  if (( release >= DOTNET_RELEASE_MIN )); then
    log ".NET Framework 4.8 already installed (release $release)"
  else
    local avail_kb
    avail_kb="$(df -k "$HOME" | awk 'NR==2 {print $4}')"
    if (( avail_kb < 8 * 1024 * 1024 )); then
      die "need at least 8 GB free to install .NET Framework. About $((avail_kb / 1024 / 1024)) GB is free."
    fi
    log "installing .NET Framework 4.8 (this takes several minutes)"
    winetricks -q dotnet48
    release="$(dotnet_release)"
    (( release >= DOTNET_RELEASE_MIN )) || die ".NET Framework 4.8 did not register (release $release)"
  fi
  wine winecfg -v win10 >/dev/null
}

ensure_overrides() {
  wine_env
  wine reg add 'HKCU\Software\Wine\DllOverrides' /v quartz /t REG_SZ /d native /f >/dev/null
}

find_installer() {
  local candidate
  for candidate in "$ROOT"/installer/KWHotel*.exe "$ROOT"/KWHotel*.exe; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

app_dir_from_stamp() {
  if [[ -f "$STAMP" ]]; then
    local dir
    dir="$(awk -F= '$1=="app"{print substr($0,5)}' "$STAMP")"
    if [[ -n "$dir" && -f "$dir/KWHotel.exe" ]]; then
      echo "$dir"
      return 0
    fi
  fi
  return 1
}

resolve_app_dir() {
  local existing installer tmp extracted
  if existing="$(app_dir_from_stamp)"; then
    echo "$existing"
    return 0
  fi
  if [[ -f "$SUPPORT/app/KWHotel.exe" ]]; then
    echo "$SUPPORT/app"
    return 0
  fi
  installer="$(find_installer || true)"
  if [[ -n "$installer" ]]; then
    ensure_7zz
    log "extracting $(basename "$installer")"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/kwhotel-extract.XXXXXX")"
    7zz x -y -o"$tmp" "$installer" >/dev/null
    if [[ -f "$tmp/KWHotel.exe" ]]; then
      extracted="$tmp"
    else
      local exe
      exe="$(find "$tmp" -name KWHotel.exe -maxdepth 3 -print -quit || true)"
      extracted="$(dirname "$exe")"
    fi
    [[ -n "${extracted:-}" && -f "$extracted/KWHotel.exe" ]] || die "installer did not contain KWHotel.exe"
    mkdir -p "$SUPPORT/app"
    # Installer plugin folders are not part of the program.
    rsync -a --delete --exclude '$PLUGINSDIR' --exclude '$TEMP' "$extracted"/ "$SUPPORT/app"/
    rm -rf "$tmp"
    # Keep a database already created by an older unpack in the home directory.
    local data_file
    for data_file in KWHotel40.sdf KWHotel.settings KWHotel.ini Dashboard.json; do
      if [[ -f "$HOME/KWHotel/$data_file" && ! -f "$SUPPORT/app/$data_file" ]]; then
        cp -p "$HOME/KWHotel/$data_file" "$SUPPORT/app/$data_file"
      fi
    done
    echo "$SUPPORT/app"
    return 0
  fi
  if [[ -f "$HOME/KWHotel/KWHotel.exe" ]]; then
    echo "$HOME/KWHotel"
    return 0
  fi
  die "KWHotel installer not found. Put KWHotel*.exe in $ROOT/installer/ and run setup again."
}

write_stamp() {
  local app_dir="$1"
  mkdir -p "$SUPPORT"
  cat >"$STAMP" <<EOF
wine=23.7.1
dotnet=4.8
app=$app_dir
EOF
}

is_ready() {
  [[ -x "$WINE_BIN/wine" ]] || return 1
  [[ -f "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/clr.dll" ]] || return 1
  app_dir_from_stamp >/dev/null || return 1
}

launch_kwhotel() {
  local app_dir
  app_dir="$(app_dir_from_stamp)" || die "KWHotel is not installed. Run setup.sh first."
  if pgrep -f 'wine-preloader KWHotel.exe' >/dev/null 2>&1; then
    log "KWHotel is already running"
    return 0
  fi
  wine_env
  log "starting KWHotel from $app_dir"
  cd "$app_dir"
  # Detach so closing Terminal does not quit the program.
  nohup "$WINE_BIN/wine" KWHotel.exe >>"$SUPPORT/kwhotel.log" 2>&1 &
  disown || true
}

setup_all() {
  mkdir -p "$SUPPORT" "$CACHE/bin"
  # Finder and a fresh Terminal do not always include Homebrew.
  if [[ -d /opt/homebrew/bin ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
  fi
  if [[ -d /usr/local/bin ]]; then
    export PATH="/usr/local/bin:$PATH"
  fi
  export PATH="$CACHE/bin:$PATH"
  xattr -dr com.apple.quarantine "$ROOT" 2>/dev/null || true
  log "KWHotel macOS setup"
  ensure_rosetta
  ensure_cabextract
  ensure_winetricks
  ensure_wine
  ensure_prefix
  ensure_dotnet
  ensure_overrides
  local app_dir
  app_dir="$(resolve_app_dir)"
  write_stamp "$app_dir"
  # The launcher bundle is unsigned when copied to another Mac.
  if [[ -d "$ROOT/KWHotel.app" ]]; then
    xattr -dr com.apple.quarantine "$ROOT/KWHotel.app" 2>/dev/null || true
    codesign --force --deep -s - "$ROOT/KWHotel.app" >/dev/null 2>&1 || true
  fi
  log "ready. App: $app_dir"
  log "prefix: $WINEPREFIX"
}
