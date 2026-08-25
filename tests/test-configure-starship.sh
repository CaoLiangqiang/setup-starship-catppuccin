#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/configure-starship.sh"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/setup-starship-test.XXXXXX")"
cleanup() { chmod -R u+w "$test_dir" 2>/dev/null || true; rm -rf "$test_dir"; }
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { if "$@" >/dev/null 2>&1; then fail "expected failure: $*"; fi; }
assert_contains() { grep -F "$1" "$2" >/dev/null || fail "missing '$1' in $2"; }

home_dir="$test_dir/home"
mkdir -p "$home_dir/.local/bin" "$home_dir/.config/fish"
printf '%s\n' '# original bash' > "$home_dir/.bashrc"
printf '%s\n' '# original zsh' > "$home_dir/.zshrc"
printf '%s\n' '# original fish' > "$home_dir/.config/fish/config.fish"
printf '%s\n' 'add_newline = false' > "$home_dir/.config/starship.toml"
cat > "$home_dir/.local/bin/starship" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod 0755 "$home_dir/.local/bin/starship"

bash "$script" --help | grep -F -- '--with-windows' >/dev/null
expect_failure bash "$script" --check --install --home "$home_dir"
expect_failure bash "$script" --check --home "$home_dir" --shells invalid
expect_failure bash "$script" --check --home "$home_dir" --shells bash,zsh,fish --skip-starship-install --skip-font-cache

checksum_fixture="$test_dir/checksum-fixture"
cp -a "$repo_root" "$checksum_fixture"
printf 'tampered\n' >> "$checksum_fixture/assets/fonts/CaskaydiaCoveNerdFont-Regular.ttf"
checksum_before="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
expect_failure bash "$checksum_fixture/scripts/configure-starship.sh" --install --home "$home_dir" --shells bash --skip-starship-install --skip-font-cache
checksum_after="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
[ "$checksum_before" = "$checksum_after" ] || fail 'checksum rejection made a mutation'

extra_font_fixture="$test_dir/extra-font-fixture"
cp -a "$repo_root" "$extra_font_fixture"
printf 'unexpected font\n' > "$extra_font_fixture/assets/fonts/Unexpected.ttf"
extra_font_before="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
expect_failure bash "$extra_font_fixture/scripts/configure-starship.sh" --install --home "$home_dir" --shells bash --skip-starship-install --skip-font-cache
extra_font_after="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
[ "$extra_font_before" = "$extra_font_after" ] || fail 'extra font rejection made a mutation'

bash "$script" --install --home "$home_dir" --shells bash,zsh,fish --skip-starship-install --skip-font-cache >/dev/null
cmp -s "$repo_root/assets/starship/catppuccin-powerline.toml" "$home_dir/.config/starship.toml" || fail 'theme was not installed'
[ -f "$home_dir/.config/starship.toml.setup-starship-catppuccin.backup" ] || fail 'original theme backup is missing'
for rc_file in "$home_dir/.bashrc" "$home_dir/.zshrc" "$home_dir/.config/fish/config.fish"; do
  assert_contains '# >>> setup-starship-catppuccin >>>' "$rc_file"
  assert_contains '# <<< setup-starship-catppuccin <<<' "$rc_file"
done
assert_contains 'starship init bash' "$home_dir/.bashrc"
assert_contains 'starship init zsh' "$home_dir/.zshrc"
assert_contains 'starship init fish' "$home_dir/.config/fish/config.fish"
for font in "$repo_root"/assets/fonts/*.ttf; do
  cmp -s "$font" "$home_dir/.local/share/fonts/CaskaydiaCoveNF/$(basename "$font")" || fail "font mismatch: $font"
done
bash "$script" --check --home "$home_dir" --shells bash,zsh,fish --skip-starship-install --skip-font-cache >/dev/null

before_hash="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
bash "$script" --install --home "$home_dir" --shells bash,zsh,fish --skip-starship-install --skip-font-cache >/dev/null
after_hash="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
[ "$before_hash" = "$after_hash" ] || fail 'second install was not idempotent'

printf '%s\n' '# user changed config' >> "$home_dir/.config/starship.toml"
remove_before="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
expect_failure bash "$script" --remove --home "$home_dir" --shells bash,zsh,fish --skip-font-cache
remove_after="$(find "$home_dir" -type f -exec sha256sum {} + | sort)"
[ "$remove_before" = "$remove_after" ] || fail 'failed remove made partial changes'
install -m 0644 "$repo_root/assets/starship/catppuccin-powerline.toml" "$home_dir/.config/starship.toml"

bash "$script" --remove --home "$home_dir" --shells bash,zsh,fish --skip-font-cache >/dev/null
assert_contains 'add_newline = false' "$home_dir/.config/starship.toml"
for rc_file in "$home_dir/.bashrc" "$home_dir/.zshrc" "$home_dir/.config/fish/config.fish"; do
  grep -F 'setup-starship-catppuccin' "$rc_file" >/dev/null && fail "remove left marker in $rc_file"
done
[ ! -d "$home_dir/.local/share/fonts/CaskaydiaCoveNF" ] || fail 'remove left the owned font directory'
[ -x "$home_dir/.local/bin/starship" ] || fail 'remove uninstalled a pre-existing Starship executable'

collision_home="$test_dir/collision"
mkdir -p "$collision_home/.local/bin"
printf '%s\n' "eval \"\$(starship init bash)\"" > "$collision_home/.bashrc"
install -m 0755 "$home_dir/.local/bin/starship" "$collision_home/.local/bin/starship"
expect_failure bash "$script" --install --home "$collision_home" --shells bash --skip-starship-install --skip-font-cache
[ ! -e "$collision_home/.config/starship.toml" ] || fail 'profile collision caused partial config installation'

symlink_home="$test_dir/symlink-home"
outside_rc="$test_dir/outside-bashrc"
mkdir -p "$symlink_home/.local/bin"
printf '%s\n' '# outside' > "$outside_rc"
ln -s "$outside_rc" "$symlink_home/.bashrc"
install -m 0755 "$home_dir/.local/bin/starship" "$symlink_home/.local/bin/starship"
expect_failure bash "$script" --install --home "$symlink_home" --shells bash --skip-starship-install --skip-font-cache
assert_contains '# outside' "$outside_rc"

printf 'PASS: configure-starship.sh is idempotent, reversible, collision-safe, and asset-complete\n'
