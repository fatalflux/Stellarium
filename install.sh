#!/usr/bin/env sh
set -eu

info() { printf '\033[0;90m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
error() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || error "curl is required but not installed."

case "$(uname -s)" in
  Darwin) platform="darwin" ;;
  Linux) platform="linux" ;;
  *) error "Unsupported operating system: $(uname -s). For Windows, use install.ps1." ;;
esac

case "$(uname -m)" in
  x86_64|amd64) architecture="x64" ;;
  arm64|aarch64) architecture="arm64" ;;
  *) error "Unsupported architecture: $(uname -m)" ;;
esac

arch_suffix=""
if [ "$architecture" = "x64" ]; then
  has_avx2=false
  if [ "$platform" = "linux" ] && grep -q -i avx2 /proc/cpuinfo 2>/dev/null; then
    has_avx2=true
  fi
  if [ "$platform" = "darwin" ] && sysctl -a 2>/dev/null | grep -q "machdep.cpu.*AVX2"; then
    has_avx2=true
  fi
  if [ "$has_avx2" = "false" ]; then
    arch_suffix="-baseline"
  fi
fi

target="${platform}-${architecture}${arch_suffix}"
zip_name="stellar-${target}.zip"
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

binary="$extract_dir/trail"
[ -f "$binary" ] || error "Archive did not contain a top-level trail binary."
chmod +x "$binary"

DST="$HOME/.local/bin"
mkdir -p "$DST" || error "Failed to create $DST"

if command -v pkill >/dev/null 2>&1; then
  if pkill -KILL -x "trail" 2>/dev/null; then
    sleep 1
    info "Stopped old trail process(es)"
  fi
fi

cp "$binary" "$DST/trail" || error "Failed to install trail"
chmod +x "$DST/trail"

case ":$PATH:" in
  *":$DST:"*) path_configured=true ;;
  *) path_configured=false ;;
esac

if [ "$path_configured" = "false" ]; then
  case "${SHELL##*/}" in
    fish)
      fish_config="$HOME/.config/fish/config.fish"
      mkdir -p "$(dirname "$fish_config")"
      grep -F 'fish_add_path -U "$HOME/.local/bin"' "$fish_config" >/dev/null 2>&1 || printf '\nfish_add_path -U "$HOME/.local/bin"\n' >> "$fish_config"
      ;;
    zsh) rc="$HOME/.zshrc"; grep -F 'export PATH="$HOME/.local/bin:$PATH"' "$rc" >/dev/null 2>&1 || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc" ;;
    bash) rc="$HOME/.bashrc"; grep -F 'export PATH="$HOME/.local/bin:$PATH"' "$rc" >/dev/null 2>&1 || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc" ;;
    *) rc="$HOME/.profile"; grep -F 'export PATH="$HOME/.local/bin:$PATH"' "$rc" >/dev/null 2>&1 || printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc" ;;
  esac
  warn "Added $DST to your shell PATH. Restart your shell or source your shell config."
else
  info "PATH already configured"
fi

info "Trail installed successfully to $DST/trail"
warn "Run 'trail' to get started."
