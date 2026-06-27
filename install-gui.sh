#!/usr/bin/env sh
set -eu

info() { printf '\033[0;90m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
error() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || error "curl is required but not installed."

case "$(uname -s)" in
  Darwin) platform="darwin" ;;
  Linux) error "Comet GUI builds are currently only available for macOS and Windows. For the CLI, use install.sh." ;;
  *) error "Unsupported operating system: $(uname -s). For Windows, use install-gui.ps1." ;;
esac

case "$(uname -m)" in
  x86_64|amd64) architecture="x64" ;;
  arm64|aarch64) architecture="arm64" ;;
  *) error "Unsupported architecture: $(uname -m)" ;;
esac

zip_name="stellarium-${platform}-${architecture}.zip"
url="https://github.com/fatalflux/Stellarium/releases/latest/download/${zip_name}"

prompt_password() {
  [ -r /dev/tty ] || error "A terminal is required to read the password."
  password=""
  backspace="$(printf '\177')"
  printf "Enter password: " >&2
  old_stty="$(stty -g < /dev/tty)"
  stty -echo -icanon min 1 time 0 < /dev/tty
  while :; do
    char="$(dd bs=1 count=1 < /dev/tty 2>/dev/null || true)"
    [ -n "$char" ] || break
    case "$char" in
      "$backspace")
        if [ -n "$password" ]; then
          password="${password%?}"
          printf '\b \b' >&2
        fi
        ;;
      *)
        password="${password}${char}"
        printf '*' >&2
        ;;
    esac
  done
  stty "$old_stty" < /dev/tty
  printf '\n' >&2
  printf '%s' "$password"
}

extract_zip() {
  zip_path="$1"
  out_dir="$2"
  zip_password="$3"
  if command -v 7zz >/dev/null 2>&1; then
    7zz x -y "-p${zip_password}" "-o${out_dir}" "$zip_path" >/dev/null
  elif command -v 7z >/dev/null 2>&1; then
    7z x -y "-p${zip_password}" "-o${out_dir}" "$zip_path" >/dev/null
  elif command -v 7za >/dev/null 2>&1; then
    7za x -y "-p${zip_password}" "-o${out_dir}" "$zip_path" >/dev/null
  elif command -v unzip >/dev/null 2>&1; then
    unzip -P "$zip_password" -q "$zip_path" -d "$out_dir" || error "Extraction failed. AES-encrypted zips usually require 7z/7zz/7za."
  else
    error "7z, 7zz, 7za, or unzip is required to extract the encrypted zip."
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

zip_path="$TMP/$zip_name"
extract_dir="$TMP/extract"
mkdir -p "$extract_dir"

info "Downloading ${zip_name}"
curl -fsSL -o "$zip_path" "$url" || error "Download failed: $url"

password="$(prompt_password)"
[ -n "$password" ] || error "Password cannot be empty."

info "Extracting encrypted archive"
extract_zip "$zip_path" "$extract_dir" "$password"

set -- "$extract_dir"/*.dmg
[ -f "$1" ] || error "Archive did not contain a top-level Comet DMG."
dmg_path="$1"

command -v open >/dev/null 2>&1 || error "open is required to launch the DMG."
open "$dmg_path"

info "Opened Comet installer: $dmg_path"
warn "Drag Comet to Applications if prompted."
warn "Press Enter after installation to clean up the downloaded installer."
IFS= read -r _ < /dev/tty || true
