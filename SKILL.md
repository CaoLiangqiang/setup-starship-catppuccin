---
name: setup-starship-catppuccin
description: Audit, install, configure, verify, and remove a consistent Starship Catppuccin Powerline prompt with bundled CaskaydiaCove Nerd Fonts across Linux, WSL, and Windows, or diagnose missing Nerd Font glyphs across terminal hosts such as Ghostty, Codex, Visual Studio Code, and Kiro. Use when Codex needs to set up Starship, separate shell initialization failures from terminal font failures, synchronize prompt appearance, preserve existing profiles, or roll back this managed configuration.
---

# Setup Starship Catppuccin

Install a consistent user-level prompt without replacing unrelated shell or Terminal settings. Treat Linux/WSL and Windows as separate state layers.

## Safety rules

- Run the status action before installing or removing.
- Require explicit user approval before changing Windows fonts, PowerShell profiles, or Windows Terminal settings.
- Require explicit user approval before changing a user-level terminal application setting; it can affect every project and workspace opened by that application.
- Treat Starship initialization and terminal font rendering as separate layers. Do not reinstall Starship when the prompt is present and only one host has missing glyphs.
- Verify `assets/fonts/SHA256SUMS` before installing, checking, or removing managed font state. Do not continue with missing, extra, or mismatched bundled font entries.
- Keep installation user-scoped. Do not add sudo, UAC, machine-wide fonts, or machine-wide PATH changes.
- Preserve existing Starship configuration in a fixed backup and preserve shell/profile files with timestamped backups.
- Refuse malformed markers, foreign Starship initialization, changed managed configuration, changed font files, and changed managed Terminal font state.
- Do not uninstall Starship during removal; package ownership may predate this skill.
- Do not claim the current terminal process reloaded PATH or fonts. Open a new shell; close all Windows Terminal windows after Windows installation.

## Workflow

1. Classify the request as terminal-host font diagnosis, managed installation or repair, or removal.
2. For a prompt that works in one host but has missing symbols in another, read [terminal font troubleshooting](references/terminal-font-troubleshooting.md), audit the failing host, obtain approval for any user-level app change, apply only that authorized setting, restart at the narrowest scope, validate the glyph sample and a real prompt, then stop. Do not enter the installer branch unless managed state is also defective or the user requested installation.
3. For managed installation, repair, or removal, read [platform behavior](references/platform-behavior.md) before targeting Windows, WSL, multiple shells, or an existing Starship installation.
4. Inspect the current OS, shells, `starship` command, config path, profile files, font state, and managed terminal settings without printing secrets.
5. Run the relevant status command and report every `CHANGE NEEDED` item.
6. Confirm whether to configure only the current Linux/WSL user or both WSL and Windows.
7. Run the installer with the narrowest selected scope.
8. Run status again, parse affected profiles/configuration, render a Starship prompt, and report the required restart scope.

## Linux and WSL

Audit the detected Bash, Zsh, and Fish installations:

```bash
bash scripts/configure-starship.sh --check
```

Install Starship under `~/.local/bin`, bundled Linux fonts, the bundled theme, and owned shell blocks:

```bash
bash scripts/configure-starship.sh --install
```

Configure both WSL and its Windows host only after explicit approval:

```bash
bash scripts/configure-starship.sh --install --with-windows
```

Use `--shells bash,zsh,fish` for an explicit shell set. Use `--home PATH`, `--skip-starship-install`, and `--skip-font-cache` only for reviewed fixture or specialized environments.

Remove owned Linux/WSL configuration and restore the original config:

```bash
bash scripts/configure-starship.sh --remove
```

## Windows

Run from Windows PowerShell 5.1 or PowerShell 7:

```powershell
.\scripts\configure-starship-windows.ps1 -Action Status
.\scripts\configure-starship-windows.ps1 -Action Install
```

The installer uses `winget --scope user`, configures installed PowerShell profiles, registers bundled fonts under `HKCU`, and sets the Windows Terminal default font to `CaskaydiaCove NF` through parsed JSONC. Windows Terminal must be installed and launched once so its user settings file exists before installation.

Remove only managed state and retain the Starship package:

```powershell
.\scripts\configure-starship-windows.ps1 -Action Remove
```

## Validation

Run repository tests before trusting script changes:

```bash
bash -n scripts/*.sh tests/*.sh
shellcheck -x scripts/*.sh tests/*.sh
bash tests/test-configure-starship.sh
npx --yes skills@1.5.23 add . --list
```

On Windows, parse and run `tests/test-configure-starship-windows.ps1`. Verify bundled fonts with `sha256sum -c assets/fonts/SHA256SUMS` on Linux. When Codex's bundled `skill-creator` is available, also run its `quick_validate.py`; do not treat it as a consumer dependency.

## Resource routing

- Run `scripts/configure-starship.sh` for Linux and WSL orchestration. Treat macOS installer use as unqualified; use the manual terminal-font workflow only for host-font diagnosis.
- Run `scripts/configure-starship-windows.ps1` for Windows fonts, PowerShell profiles, Starship, and Windows Terminal.
- Read `references/terminal-font-troubleshooting.md` when glyphs differ between Ghostty, Codex, Visual Studio Code, Kiro, or another terminal host.
- Read `references/platform-behavior.md` for managed paths, backup/rollback behavior, restart scope, and supported boundaries.
- Read `references/sources.md` before changing installer URLs, package identifiers, font family names, bundled licenses, or the preset baseline.
- Copy `assets/starship/catppuccin-powerline.toml`; do not reconstruct the Powerline layout ad hoc.
- Install fonts only from `assets/fonts` after verifying `SHA256SUMS`; retain `OFL.txt` with redistributed font files.
