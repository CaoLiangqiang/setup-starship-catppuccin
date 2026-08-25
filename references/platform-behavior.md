# Platform Behavior

## Delivery model

The repository ships a source-only Agent Skill through versioned Git tags and GitHub Releases. Published tags are treated as append-only project policy and version identifiers are never reused. The repository does not publish a standalone installer package or binary artifact. The Bash and PowerShell scripts apply the versioned configuration and font assets from the checked-out release; Starship itself continues to come from the official upstream installer or the user-scoped WinGet package when missing.

## Supported scope

| Layer | Managed state |
| --- | --- |
| Linux/WSL | `~/.local/bin/starship`, `~/.config/starship.toml`, user font files, and owned Bash/Zsh/Fish blocks |
| Windows | User-scoped WinGet Starship package, `%USERPROFILE%\.config\starship.toml`, user fonts, installed PowerShell profiles, and Windows Terminal defaults |

The bundled theme is Catppuccin Powerline with the Mocha palette. It intentionally omits C, Rust, Go, Node.js, Bun, PHP, Java, Kotlin, Haskell, and Python version segments. It retains OS, username, directory, Git state, Conda environment, time, and command duration.

The Linux/WSL installer requires Bash 4 or newer and GNU/Linux tooling. macOS automation is intentionally rejected before GNU-specific file operations; the host-font troubleshooting workflow remains manual and does not expand the release-qualified platform set.

## Asset integrity

Both installers require `assets/fonts/SHA256SUMS` to contain exactly the four managed font entries and verify each bundled font before status, install, or removal work. A missing, duplicate, extra, or mismatched entry stops before managed state changes.

## Ownership and rollback

Shell profiles use these exact markers:

```text
# >>> setup-starship-catppuccin >>>
# <<< setup-starship-catppuccin <<<
```

Installation refuses foreign Starship initialization instead of adding a second hook. Timestamped profile backups remain next to the original file.

The first unmanaged `starship.toml` is saved as `starship.toml.setup-starship-catppuccin.backup`. A SHA-256 sidecar records the installed asset. Removal restores the backup only when the current file still matches the recorded managed version. A user-edited managed config blocks removal until reviewed.

Font files follow the same rule: replace only after preserving a conflicting file, and remove only when the installed bytes still match the bundled asset. On Windows, an owned state file records prior file presence plus whether each user font registry value existed and its exact prior value. Ambiguous same-target files are preserved as user state unless a matching managed config and hash stamp prove a legacy v0.1 installation. Removal refuses changed managed registration state, restores the conflicting file and registry value together, and reloads the restored file when applicable. Removal retains the Starship executable/package because the package may have existed before this skill.

Windows Terminal settings are parsed as JSONC, including comments and trailing commas outside strings. The first managed write creates a timestamped backup and normalizes the updated file to strict JSON. Installation records only the prior `profiles.defaults.font.face` state and writes `CaskaydiaCove NF`; removal restores that property without reverting unrelated settings changed later.

## Platform details

### Linux and WSL

The Bash installer uses Starship's official install script only when no executable is available. It installs to `~/.local/bin`, then places an owned PATH and initialization block in each selected shell profile. Linux font files go to `~/.local/share/fonts/CaskaydiaCoveNF`.

Linux font installation does not affect a Windows-hosted WSL terminal. Use `--with-windows` to invoke the Windows installer through the explicit mounted PowerShell path. This does not re-import Windows PATH into WSL.

### Windows

The Windows installer uses the `Starship.Starship` WinGet package with `--scope user`. It registers four CaskaydiaCove files under the current-user font registry using full absolute paths. Windows exposes the bundled family as `CaskaydiaCove NF`; using `CaskaydiaCove Nerd Font` in Terminal settings produces a missing-font warning.

Configure the Windows PowerShell 5.1 profile and the PowerShell 7 profile only when PowerShell 7 is installed or its profile directory exists. Keep existing functions, aliases, proxy configuration, and PSReadLine setup intact.

Production mode derives profile, font, registry, and Windows Terminal paths from the current user's environment. Arbitrary writable target overrides are limited to isolated test mode. Windows Terminal absence is not a successful reduced configuration: status reports `CHANGE NEEDED`, and installation stops during preflight before managed writes with an instruction to install and launch Windows Terminal once.

## Failure semantics

Install preflight rejects known checksum, path, ownership, profile-marker, config-hash, registry-state, and Terminal-settings conflicts before managed writes. Component operations are idempotent and removal is targeted, but Linux plus Windows orchestration is not a cross-operating-system transaction. If an external package manager, font API, filesystem, or WSL bridge fails after a component changes, run status to identify the exact remaining state, then rerun install or use removal after reviewing the reported ownership checks. Do not assume a failed process rolled back a successful upstream Starship package installation.

## Restart scope

- Shell profile or config only: start a new shell. Starship config changes appear on the next prompt when Starship is already active.
- WinGet user PATH: close all Windows Terminal windows and start Windows Terminal again.
- Windows user fonts or Terminal defaults: close all Windows Terminal windows and start it again. A new tab in an old Terminal process can inherit stale PATH and font enumeration.
- WSL PATH isolation changes are outside this skill. Do not run `wsl --shutdown` unless another workflow changed WSL host configuration.
