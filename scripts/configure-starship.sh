#!/usr/bin/env bash
set -Eeuo pipefail

mode='check'
action_count=0
home_dir="${HOME:-}"
shells='auto'
with_windows=0
skip_starship_install=0
skip_font_cache=0

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_asset="$repo_root/assets/starship/catppuccin-powerline.toml"
font_asset_dir="$repo_root/assets/fonts"
font_checksums="$font_asset_dir/SHA256SUMS"
marker_start='# >>> setup-starship-catppuccin >>>'
marker_end='# <<< setup-starship-catppuccin <<<'
managed_fonts=(
  'CaskaydiaCoveNerdFont-Regular.ttf'
  'CaskaydiaCoveNerdFont-Bold.ttf'
  'CaskaydiaCoveNerdFont-Italic.ttf'
  'CaskaydiaCoveNerdFont-BoldItalic.ttf'
)

usage() {
  printf '%s\n' \
    'Usage: configure-starship.sh [--check|--install|--remove] [options]' \
    '' \
    '  --check                  report state without changing files (default)' \
    '  --install                install Starship, theme, fonts, and shell blocks' \
    '  --remove                 remove owned files/blocks and restore backups' \
    '  --home PATH              target user home directory' \
    '  --shells LIST            auto or comma-separated bash,zsh,fish' \
    '  --with-windows           also run the Windows PowerShell installer from WSL' \
    '  --skip-starship-install  require an existing Starship executable' \
    '  --skip-font-cache        do not run fc-cache after font changes'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check|--install|--remove)
      mode="${1#--}"
      action_count=$((action_count + 1))
      shift
      ;;
    --home|--shells)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      case "$1" in
        --home) home_dir="$2" ;;
        --shells) shells="$2" ;;
      esac
      shift 2
      ;;
    --with-windows) with_windows=1; shift ;;
    --skip-starship-install) skip_starship_install=1; shift ;;
    --skip-font-cache) skip_font_cache=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ "$action_count" -gt 1 ]; then
  printf 'Specify at most one action: --check, --install, or --remove.\n' >&2
  exit 2
fi
if [ "$(uname -s)" != 'Linux' ]; then
  printf 'Unsupported platform: configure-starship.sh is release-qualified only for GNU/Linux and WSL. Use the manual host-font workflow on macOS.\n' >&2
  exit 2
fi
if [ -z "$home_dir" ] || [ "$home_dir" = '/' ] || [ ! -d "$home_dir" ]; then
  printf 'Refusing invalid home directory: %s\n' "${home_dir:-<empty>}" >&2
  exit 2
fi
home_dir="$(cd "$home_dir" && pwd -P)"
current_uid="$(id -u)"
config_dir="$home_dir/.config"
config_file="$config_dir/starship.toml"
config_backup="$config_file.setup-starship-catppuccin.backup"
config_stamp="$config_file.setup-starship-catppuccin.sha256"
local_bin="$home_dir/.local/bin"
font_dir="$home_dir/.local/share/fonts/CaskaydiaCoveNF"

for required_asset in "$config_asset" "$font_asset_dir/OFL.txt" "$font_checksums"; do
  [ -f "$required_asset" ] || { printf 'Missing bundled asset: %s\n' "$required_asset" >&2; exit 2; }
done
for font_name in "${managed_fonts[@]}"; do
  required_asset="$font_asset_dir/$font_name"
  [ -f "$required_asset" ] || { printf 'Missing bundled font: %s\n' "$required_asset" >&2; exit 2; }
done

verify_font_assets() {
  local line hash name count=0 asset_count=0 asset
  local -A expected=() seen=()
  for name in "${managed_fonts[@]}"; do expected["$name"]=1; done
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ ! "$line" =~ ^([[:xdigit:]]{64})\ \ (.+)$ ]]; then
      printf 'Invalid bundled font checksum entry: %s\n' "$line" >&2
      return 1
    fi
    hash="${BASH_REMATCH[1],,}"
    name="${BASH_REMATCH[2]}"
    if [ -z "${expected[$name]:-}" ] || [ -n "${seen[$name]:-}" ]; then
      printf 'Unexpected or duplicate bundled font checksum entry: %s\n' "$name" >&2
      return 1
    fi
    seen["$name"]=1
    if [ "$(sha256sum "$font_asset_dir/$name" | awk '{print $1}')" != "$hash" ]; then
      printf 'Bundled font checksum mismatch: %s\n' "$font_asset_dir/$name" >&2
      return 1
    fi
    count=$((count + 1))
  done < "$font_checksums"
  if [ "$count" -ne "${#managed_fonts[@]}" ]; then
    printf 'Bundled font checksum manifest must contain exactly %s managed fonts.\n' "${#managed_fonts[@]}" >&2
    return 1
  fi
  for name in "${managed_fonts[@]}"; do
    [ -n "${seen[$name]:-}" ] || { printf 'Missing bundled font checksum entry: %s\n' "$name" >&2; return 1; }
  done
  for asset in "$font_asset_dir"/*.ttf; do
    name="$(basename "$asset")"
    if [ -z "${expected[$name]:-}" ]; then
      printf 'Unexpected bundled font file: %s\n' "$asset" >&2
      return 1
    fi
    asset_count=$((asset_count + 1))
  done
  if [ "$asset_count" -ne "${#managed_fonts[@]}" ]; then
    printf 'Bundled font directory must contain exactly %s managed font files.\n' "${#managed_fonts[@]}" >&2
    return 1
  fi
}

verify_font_assets

require_inside_home() {
  local path="$1" resolved
  resolved="$(realpath -m "$path")"
  case "$resolved" in
    "$home_dir"|"$home_dir"/*) ;;
    *) printf 'Target resolves outside --home: %s\n' "$path" >&2; return 1 ;;
  esac
}

require_regular_or_missing() {
  local path="$1"
  if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
    printf 'Expected a regular file or missing path: %s\n' "$path" >&2
    return 1
  fi
}

require_current_owner() {
  local path="$1" owner
  [ ! -e "$path" ] && return 0
  owner="$(stat -c '%u' -- "$path" 2>/dev/null || true)"
  if [ "$owner" != "$current_uid" ]; then
    printf 'Path must be owned by the current user: %s\n' "$path" >&2
    return 1
  fi
}

discover_shells() {
  local found=() shell
  for shell in bash zsh fish; do
    case "$shell" in
      bash) [ -e "$home_dir/.bashrc" ] || command -v bash >/dev/null 2>&1 || continue ;;
      zsh) [ -e "$home_dir/.zshrc" ] || command -v zsh >/dev/null 2>&1 || continue ;;
      fish) [ -e "$home_dir/.config/fish/config.fish" ] || command -v fish >/dev/null 2>&1 || continue ;;
    esac
    found+=("$shell")
  done
  [ "${#found[@]}" -gt 0 ] || found=(bash)
  (IFS=,; printf '%s\n' "${found[*]}")
}

if [ "$shells" = 'auto' ]; then shells="$(discover_shells)"; fi
IFS=',' read -r -a selected_shells <<< "$shells"
[ "${#selected_shells[@]}" -gt 0 ] || { printf 'No shells selected.\n' >&2; exit 2; }
for shell in "${selected_shells[@]}"; do
  case "$shell" in bash|zsh|fish) ;; *) printf 'Unsupported shell: %s\n' "$shell" >&2; exit 2 ;; esac
done

rc_file_for() {
  case "$1" in
    bash) printf '%s\n' "$home_dir/.bashrc" ;;
    zsh) printf '%s\n' "$home_dir/.zshrc" ;;
    fish) printf '%s\n' "$home_dir/.config/fish/config.fish" ;;
  esac
}

render_block() {
  local shell="$1"
  printf '%s\n' "$marker_start"
  case "$shell" in
    bash|zsh)
      # shellcheck disable=SC2016
      printf '%s\n' \
        'case ":$PATH:" in' \
        '  *":$HOME/.local/bin:"*) ;;' \
        '  *) export PATH="$HOME/.local/bin:$PATH" ;;' \
        'esac' \
        "eval \"\$(starship init $shell)\""
      ;;
    fish)
      # shellcheck disable=SC2016
      printf '%s\n' \
        'if not contains -- $HOME/.local/bin $PATH' \
        '    fish_add_path --prepend $HOME/.local/bin' \
        'end' \
        'starship init fish | source'
      ;;
  esac
  printf '%s\n' "$marker_end"
}

block_state() {
  local file="$1" shell="$2" starts ends extracted expected
  [ -L "$file" ] && { printf 'symlink\n'; return; }
  [ -e "$file" ] || { printf 'missing\n'; return; }
  starts="$(grep -Fxc "$marker_start" "$file" || true)"
  ends="$(grep -Fxc "$marker_end" "$file" || true)"
  if [ "$starts" -eq 0 ] && [ "$ends" -eq 0 ]; then
    if grep -F "starship init $shell" "$file" >/dev/null 2>&1; then printf 'foreign\n'; else printf 'absent\n'; fi
    return
  fi
  if [ "$starts" -ne 1 ] || [ "$ends" -ne 1 ]; then printf 'malformed\n'; return; fi
  extracted="$(awk -v start="$marker_start" -v end="$marker_end" '
    $0 == start { active = 1 }
    active { print }
    $0 == end { exit }
  ' "$file")"
  expected="$(render_block "$shell")"
  if [ "$extracted" = "$expected" ]; then printf 'owned\n'; else printf 'collision\n'; fi
}

backup_file() {
  local file="$1" backup
  backup="$(mktemp "${file}.setup-starship-catppuccin.backup.XXXXXX")"
  cp --preserve=mode,timestamps -- "$file" "$backup"
  printf 'Backup: %s\n' "$backup"
}

replace_atomically() {
  local file="$1" renderer="$2" shell="${3:-}" dir base temp_file
  dir="$(dirname "$file")"
  base="$(basename "$file")"
  mkdir -p "$dir"
  temp_file="$(mktemp "$dir/.${base}.setup-starship-catppuccin.tmp.XXXXXX")"
  if [ -e "$file" ]; then chmod --reference="$file" "$temp_file"; else chmod 0644 "$temp_file"; fi
  "$renderer" "$file" "$shell" > "$temp_file"
  mv -f -- "$temp_file" "$file"
}

render_install_rc() {
  local file="$1" shell="$2"
  if [ -e "$file" ]; then cat -- "$file"; printf '\n'; fi
  render_block "$shell"
}

render_remove_rc() {
  local file="$1"
  awk -v start="$marker_start" -v end="$marker_end" '
    $0 == start { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$file"
}

install_rc_block() {
  local shell="$1" file state
  file="$(rc_file_for "$shell")"
  require_inside_home "$file"
  require_regular_or_missing "$file"
  state="$(block_state "$file" "$shell")"
  case "$state" in
    owned) return ;;
    missing|absent) ;;
    *) printf 'Refusing %s Starship block state in %s\n' "$state" "$file" >&2; return 1 ;;
  esac
  if [ -e "$file" ]; then require_current_owner "$file"; backup_file "$file"; fi
  replace_atomically "$file" render_install_rc "$shell"
  printf 'Installed %s startup block: %s\n' "$shell" "$file"
}

remove_rc_block() {
  local shell="$1" file state
  file="$(rc_file_for "$shell")"
  state="$(block_state "$file" "$shell")"
  case "$state" in
    missing|absent|foreign) printf 'No owned %s startup block: %s\n' "$shell" "$file"; return ;;
    owned) ;;
    *) printf 'Refusing %s Starship block state in %s\n' "$state" "$file" >&2; return 1 ;;
  esac
  require_current_owner "$file"
  backup_file "$file"
  replace_atomically "$file" render_remove_rc
  printf 'Removed %s startup block: %s\n' "$shell" "$file"
}

starship_path() {
  if [ -x "$local_bin/starship" ]; then printf '%s\n' "$local_bin/starship"; return 0; fi
  command -v starship 2>/dev/null || return 1
}

install_starship() {
  local installer
  if starship_path >/dev/null; then return; fi
  if [ "$skip_starship_install" -eq 1 ]; then
    printf 'Starship is missing and --skip-starship-install was selected.\n' >&2
    return 1
  fi
  mkdir -p "$local_bin"
  installer="$(mktemp "${TMPDIR:-/tmp}/starship-install.XXXXXX")"
  trap 'rm -f -- "${installer:-}"' RETURN
  curl -fsSL --retry 3 https://starship.rs/install.sh -o "$installer"
  sh "$installer" --yes --bin-dir "$local_bin"
  rm -f -- "$installer"
  trap - RETURN
  [ -x "$local_bin/starship" ] || { printf 'Starship installer did not create %s\n' "$local_bin/starship" >&2; return 1; }
}

install_config() {
  local current_hash='' recorded_hash='' asset_hash
  asset_hash="$(sha256sum "$config_asset" | awk '{print $1}')"
  require_inside_home "$config_file"
  for path in "$config_file" "$config_backup" "$config_stamp"; do require_regular_or_missing "$path"; done
  if [ -f "$config_file" ]; then current_hash="$(sha256sum "$config_file" | awk '{print $1}')"; fi
  if [ -f "$config_stamp" ]; then recorded_hash="$(tr -d '[:space:]' < "$config_stamp")"; fi
  if [ -n "$recorded_hash" ] && [ -n "$current_hash" ] && [ "$current_hash" != "$recorded_hash" ]; then
    printf 'Refusing to overwrite a Starship config changed after installation: %s\n' "$config_file" >&2
    return 1
  fi
  mkdir -p "$config_dir"
  if [ -f "$config_file" ] && [ ! -f "$config_backup" ] && [ -z "$recorded_hash" ]; then
    cp --preserve=mode,timestamps -- "$config_file" "$config_backup"
    printf 'Saved original Starship config: %s\n' "$config_backup"
  fi
  install -m 0644 "$config_asset" "$config_file"
  printf '%s\n' "$asset_hash" > "$config_stamp"
  printf 'Installed Catppuccin Powerline config: %s\n' "$config_file"
}

remove_config() {
  local current_hash recorded_hash
  [ -f "$config_stamp" ] || { printf 'No owned Starship config stamp.\n'; return; }
  recorded_hash="$(tr -d '[:space:]' < "$config_stamp")"
  if [ -f "$config_file" ]; then
    current_hash="$(sha256sum "$config_file" | awk '{print $1}')"
    if [ "$current_hash" != "$recorded_hash" ]; then
      printf 'Refusing to remove a Starship config changed after installation: %s\n' "$config_file" >&2
      return 1
    fi
  fi
  if [ -f "$config_backup" ]; then
    mv -f -- "$config_backup" "$config_file"
    printf 'Restored original Starship config: %s\n' "$config_file"
  else
    rm -f -- "$config_file"
    printf 'Removed owned Starship config: %s\n' "$config_file"
  fi
  rm -f -- "$config_stamp"
}

install_fonts() {
  local asset target backup font_name
  mkdir -p "$font_dir"
  for font_name in "${managed_fonts[@]}"; do
    asset="$font_asset_dir/$font_name"
    target="$font_dir/$font_name"
    backup="$target.setup-starship-catppuccin.backup"
    require_regular_or_missing "$target"
    require_regular_or_missing "$backup"
    if [ -f "$target" ] && ! cmp -s "$asset" "$target" && [ ! -f "$backup" ]; then
      cp --preserve=mode,timestamps -- "$target" "$backup"
    fi
    install -m 0644 "$asset" "$target"
  done
  install -m 0644 "$font_asset_dir/OFL.txt" "$font_dir/OFL.txt"
  if [ "$skip_font_cache" -eq 0 ] && command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$font_dir" >/dev/null; fi
  printf 'Installed CaskaydiaCove Nerd Font assets: %s\n' "$font_dir"
}

remove_fonts() {
  local asset target backup changed=0 font_name
  [ -d "$font_dir" ] || { printf 'No owned Linux font directory.\n'; return; }
  for font_name in "${managed_fonts[@]}"; do
    asset="$font_asset_dir/$font_name"
    target="$font_dir/$font_name"
    backup="$target.setup-starship-catppuccin.backup"
    if [ -f "$target" ] && ! cmp -s "$asset" "$target"; then
      printf 'Preserving changed font file: %s\n' "$target" >&2
      changed=1
      continue
    fi
    if [ -f "$backup" ]; then mv -f -- "$backup" "$target"; else rm -f -- "$target"; fi
  done
  rm -f -- "$font_dir/OFL.txt"
  if [ "$skip_font_cache" -eq 0 ] && command -v fc-cache >/dev/null 2>&1; then fc-cache -f "$font_dir" >/dev/null || true; fi
  [ "$changed" -eq 0 ] || return 1
  rmdir "$font_dir" 2>/dev/null || true
  printf 'Removed owned Linux font assets.\n'
}

check_local_state() {
  local ready=1 shell file asset target font_name
  starship_path >/dev/null || { printf 'CHANGE NEEDED: Starship executable is missing.\n'; ready=0; }
  cmp -s "$config_asset" "$config_file" || { printf 'CHANGE NEEDED: Starship config differs or is missing.\n'; ready=0; }
  for font_name in "${managed_fonts[@]}"; do
    asset="$font_asset_dir/$font_name"
    target="$font_dir/$font_name"
    cmp -s "$asset" "$target" || { printf 'CHANGE NEEDED: font differs or is missing: %s\n' "$target"; ready=0; }
  done
  for shell in "${selected_shells[@]}"; do
    file="$(rc_file_for "$shell")"
    [ "$(block_state "$file" "$shell")" = 'owned' ] || { printf 'CHANGE NEEDED: %s startup block is not installed.\n' "$shell"; ready=0; }
  done
  if [ "$ready" -eq 1 ]; then printf 'OK: Starship, Catppuccin config, fonts, and shell blocks are ready.\n'; return 0; fi
  return 1
}

preflight_install() {
  local shell file state current_hash recorded_hash path asset target font_name
  for path in "$config_file" "$config_backup" "$config_stamp"; do require_regular_or_missing "$path"; done
  if [ -f "$config_stamp" ] && [ -f "$config_file" ]; then
    recorded_hash="$(tr -d '[:space:]' < "$config_stamp")"
    current_hash="$(sha256sum "$config_file" | awk '{print $1}')"
    if [ "$current_hash" != "$recorded_hash" ]; then
      printf 'Refusing to overwrite a Starship config changed after installation: %s\n' "$config_file" >&2
      return 1
    fi
  fi
  for shell in "${selected_shells[@]}"; do
    file="$(rc_file_for "$shell")"
    require_regular_or_missing "$file"
    state="$(block_state "$file" "$shell")"
    case "$state" in owned|missing|absent) ;; *) printf 'Refusing %s Starship block state in %s\n' "$state" "$file" >&2; return 1 ;; esac
  done
  for font_name in "${managed_fonts[@]}"; do
    target="$font_dir/$font_name"
    require_regular_or_missing "$target"
    require_regular_or_missing "$target.setup-starship-catppuccin.backup"
  done
}

preflight_remove() {
  local shell file state current_hash recorded_hash asset target font_name
  if [ -f "$config_stamp" ] && [ -f "$config_file" ]; then
    recorded_hash="$(tr -d '[:space:]' < "$config_stamp")"
    current_hash="$(sha256sum "$config_file" | awk '{print $1}')"
    if [ "$current_hash" != "$recorded_hash" ]; then
      printf 'Refusing to remove a Starship config changed after installation: %s\n' "$config_file" >&2
      return 1
    fi
  fi
  for shell in "${selected_shells[@]}"; do
    file="$(rc_file_for "$shell")"
    state="$(block_state "$file" "$shell")"
    case "$state" in owned|missing|absent|foreign) ;; *) printf 'Refusing %s Starship block state in %s\n' "$state" "$file" >&2; return 1 ;; esac
  done
  for font_name in "${managed_fonts[@]}"; do
    asset="$font_asset_dir/$font_name"
    target="$font_dir/$font_name"
    if [ -f "$target" ] && ! cmp -s "$asset" "$target"; then
      printf 'Refusing to remove a changed font file: %s\n' "$target" >&2
      return 1
    fi
  done
}

run_windows_action() {
  local ps_script="$repo_root/scripts/configure-starship-windows.ps1" ps_exe='' ps_path action
  [ -n "${WSL_DISTRO_NAME:-}" ] || { printf '--with-windows requires WSL.\n' >&2; return 1; }
  for candidate in \
    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe \
    /mnt/c/Program\ Files/PowerShell/7/pwsh.exe; do
    if [ -x "$candidate" ]; then ps_exe="$candidate"; break; fi
  done
  [ -n "$ps_exe" ] || { printf 'Windows PowerShell executable not found.\n' >&2; return 1; }
  command -v wslpath >/dev/null 2>&1 || { printf 'wslpath is required for --with-windows.\n' >&2; return 1; }
  ps_path="$(wslpath -w "$ps_script")"
  case "$mode" in check) action='Status' ;; install) action='Install' ;; remove) action='Remove' ;; esac
  "$ps_exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$ps_path" -Action "$action"
}

for target in "$config_dir" "$local_bin" "$font_dir"; do require_inside_home "$target"; done
require_current_owner "$home_dir"

case "$mode" in
  check)
    local_status=0
    check_local_state || local_status=$?
    if [ "$with_windows" -eq 1 ]; then run_windows_action || local_status=1; fi
    exit "$local_status"
    ;;
  install)
    preflight_install
    install_starship
    install_config
    install_fonts
    for shell in "${selected_shells[@]}"; do install_rc_block "$shell"; done
    if [ "$with_windows" -eq 1 ]; then run_windows_action; fi
    check_local_state
    ;;
  remove)
    preflight_remove
    status=0
    for shell in "${selected_shells[@]}"; do remove_rc_block "$shell" || status=1; done
    remove_config || status=1
    remove_fonts || status=1
    if [ "$with_windows" -eq 1 ]; then run_windows_action || status=1; fi
    exit "$status"
    ;;
esac
