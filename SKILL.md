---
name: setup-starship-catppuccin
description: Audit, install, configure, verify, and remove a consistent Starship Catppuccin Powerline prompt with bundled CaskaydiaCove Nerd Fonts across Linux, WSL, Bash, Zsh, Fish, Windows PowerShell 5.1 or PowerShell 7, and Windows Terminal. Use when Codex needs to set up Starship, repair missing Powerline glyphs, synchronize prompt appearance across Windows and WSL, preserve existing shell profiles during prompt changes, or roll back this managed terminal configuration.
---

# Setup Starship Catppuccin

Install a consistent user-level prompt without replacing unrelated shell or Terminal settings. Treat Linux/WSL and Windows as separate state layers.

## Safety rules

- Run the status action before installing or removing.
- Require explicit user approval before changing Windows fonts, PowerShell profiles, or Windows Terminal settings.
- Keep installation user-scoped. Do not add sudo, UAC, machine-wide fonts, or machine-wide PATH changes.
- Preserve existing Starship configuration in a fixed backup and preserve shell/profile files with timestamped backups.
- Refuse malformed markers, foreign Starship initialization, changed managed configuration, changed font files, and changed managed Terminal font state.
- Do not uninstall Starship during removal; package ownership may predate this skill.
- Do not claim the current terminal process reloaded PATH or fonts. Open a new shell; close all Windows Terminal windows after Windows installation.

## Workflow

1. Read [platform behavior](references/platform-behavior.md) before targeting Windows, WSL, multiple shells, or an existing Starship installation.
2. Inspect the current OS, shells, `starship` command, config path, profile files, font state, and Windows Terminal settings without printing secrets.
3. Run the relevant status command and report every `CHANGE NEEDED` item.
4. Confirm whether to configure only the current Linux/WSL user or both WSL and Windows.
5. Run the installer with the narrowest selected scope.
6. Run status again, parse affected profiles/configuration, render a Starship prompt, and report the required restart scope.

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

The installer uses `winget --scope user`, configures installed PowerShell profiles, registers bundled fonts under `HKCU`, and sets the Windows Terminal default font to `CaskaydiaCove NF` through parsed JSON.

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
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py .
```

On Windows, parse and run `tests/test-configure-starship-windows.ps1`. Verify bundled fonts with `sha256sum -c assets/fonts/SHA256SUMS` on Linux.

## Resource routing

- Run `scripts/configure-starship.sh` for Linux, macOS-style user shells, and WSL orchestration.
- Run `scripts/configure-starship-windows.ps1` for Windows fonts, PowerShell profiles, Starship, and Windows Terminal.
- Read `references/platform-behavior.md` for managed paths, backup/rollback behavior, restart scope, and supported boundaries.
- Read `references/sources.md` before changing installer URLs, package identifiers, font family names, bundled licenses, or the preset baseline.
- Copy `assets/starship/catppuccin-powerline.toml`; do not reconstruct the Powerline layout ad hoc.
- Install fonts only from `assets/fonts` after verifying `SHA256SUMS`; retain `OFL.txt` with redistributed font files.
