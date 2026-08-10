<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Setup Starship Catppuccin installs one consistent and reversible Powerline prompt across WSL and Windows terminals">
</p>

<p align="center">
  <a href="https://github.com/CaoLiangqiang/setup-starship-catppuccin/releases/latest"><img src="https://img.shields.io/github/v/release/CaoLiangqiang/setup-starship-catppuccin?style=flat-square&color=f38ba8" alt="Latest release"></a>
  <a href="https://github.com/CaoLiangqiang/setup-starship-catppuccin/actions/workflows/validate.yml"><img src="https://img.shields.io/github/actions/workflow/status/CaoLiangqiang/setup-starship-catppuccin/validate.yml?branch=main&style=flat-square&label=validate" alt="Validation status"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/CaoLiangqiang/setup-starship-catppuccin?style=flat-square&color=a6e3a1" alt="MIT license"></a>
  <img src="https://img.shields.io/badge/WSL%20%2B%20Windows-supported-89b4fa?style=flat-square" alt="WSL and Windows supported">
</p>

`setup-starship-catppuccin` is an Agent Skill that installs one consistent Starship prompt across Linux or WSL shells and the Windows host. It carries the exact Catppuccin Powerline configuration, CaskaydiaCove Nerd Fonts, deterministic installers, and rollback rules needed to reproduce the setup without replacing unrelated terminal settings.

## See the target state first

The bundled prompt uses Catppuccin Mocha and keeps the information useful during everyday repository work:

```text
OS  user  ~/workspace/project  git:main +1  conda:env  14:32  128ms
>
```

It intentionally omits language and runtime versions. The visible segments are OS, username, directory, Git branch and status, Conda environment, time, command duration, and the final status character.

## Quick start

Install the Skill with the standard Agent Skills CLI:

```bash
npx skills add CaoLiangqiang/setup-starship-catppuccin \
  --skill setup-starship-catppuccin
```

Then ask Codex to use it:

```text
Use $setup-starship-catppuccin to audit my current terminal setup, then install
the Catppuccin Powerline prompt for WSL and Windows.
```

For direct, deterministic operation from a checkout, audit before making changes:

```bash
git clone git@github.com:CaoLiangqiang/setup-starship-catppuccin.git
cd setup-starship-catppuccin

bash scripts/configure-starship.sh --check
bash scripts/configure-starship.sh --install
```

Add `--with-windows` only when you also want to change Windows fonts, PowerShell profiles, and Windows Terminal:

```bash
bash scripts/configure-starship.sh --install --with-windows
```

Close every Windows Terminal window and start it again after a Windows installation so the process reloads the user PATH and font registry.

## What it manages

| Layer | Managed state |
| --- | --- |
| Linux / WSL | User-level Starship binary, `~/.config/starship.toml`, four bundled fonts, and owned Bash, Zsh, or Fish initialization blocks |
| Windows | User-scoped WinGet Starship package, PowerShell 5.1 and PowerShell 7 profiles, per-user fonts, and the Windows Terminal default font |
| Theme | Catppuccin Mocha Powerline layout with repository, environment, time, and command-status information |
| Recovery | Fixed configuration backup, timestamped profile backups, content hashes, managed markers, collision checks, and targeted removal |

Windows Terminal must use the family name `CaskaydiaCove NF`. The longer name `CaskaydiaCove Nerd Font` is not the installed family name and causes the Terminal missing-font warning.

## Safety model

- `--check` is read-only and reports every `CHANGE NEEDED` item.
- Linux and WSL installation stays under the current user's home directory.
- Windows installation uses WinGet `--scope user` and the current-user font registry.
- Windows changes are separate and opt-in; the Linux installer never enables them silently.
- Managed blocks have exact ownership markers. Foreign Starship initialization or malformed markers stop the operation.
- Removal restores the original Starship config only when the managed copy still matches its recorded hash.
- Starship itself is retained during removal because it may have existed before this Skill.

The complete ownership and restart contract is documented in [platform behavior](references/platform-behavior.md).

## Choose the shell scope

Shell discovery covers Bash, Zsh, and Fish. Override it when a machine should manage only a specific set:

```bash
bash scripts/configure-starship.sh --install --shells bash,zsh
```

Windows can also be managed directly from Windows PowerShell 5.1 or PowerShell 7:

```powershell
.\scripts\configure-starship-windows.ps1 -Action Status
.\scripts\configure-starship-windows.ps1 -Action Install
```

## Roll back

Remove only state owned by this repository:

```bash
bash scripts/configure-starship.sh --remove
```

For Windows-only removal:

```powershell
.\scripts\configure-starship-windows.ps1 -Action Remove
```

If a managed config, font, profile block, or Terminal setting was edited after installation, removal stops instead of overwriting the newer user change.

## Repository map

```text
assets/fonts/          CaskaydiaCove Nerd Font files, OFL license, checksums
assets/starship/       Catppuccin Powerline configuration
scripts/               Linux/WSL and Windows installers
tests/                 Isolated idempotence, collision, and rollback fixtures
references/            Platform behavior and primary upstream sources
SKILL.md               Agent workflow, safety rules, and resource routing
```

## Validate a checkout

```bash
bash -n scripts/*.sh tests/*.sh
shellcheck -x scripts/*.sh tests/*.sh
bash tests/test-configure-starship.sh
(cd assets/fonts && sha256sum -c SHA256SUMS)
npx skills add . --list
python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py .
```

On Windows, parse the PowerShell sources and run:

```powershell
.\tests\test-configure-starship-windows.ps1
```

GitHub Actions runs the Linux and Windows validation paths for every push and pull request.

## Compatibility

- Linux and WSL: Bash, Zsh, and Fish with standard user-level font discovery.
- Windows: Windows PowerShell 5.1 or PowerShell 7, WinGet, and Windows Terminal.
- Font registration and Terminal configuration are Windows-user scoped; no UAC or machine-wide font installation is required.
- macOS is not release-qualified by the current test suite.

## Sources and licenses

Installer behavior and bundled assets are tied to the primary sources listed in [references/sources.md](references/sources.md).

Repository scripts and documentation are released under the [MIT License](LICENSE). Bundled CaskaydiaCove font files remain under the [SIL Open Font License 1.1](assets/fonts/OFL.txt).
