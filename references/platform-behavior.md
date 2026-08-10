# Platform Behavior

## Supported scope

| Layer | Managed state |
| --- | --- |
| Linux/WSL | `~/.local/bin/starship`, `~/.config/starship.toml`, user font files, and owned Bash/Zsh/Fish blocks |
| Windows | User-scoped WinGet Starship package, `%USERPROFILE%\.config\starship.toml`, user fonts, installed PowerShell profiles, and Windows Terminal defaults |

The bundled theme is Catppuccin Powerline with the Mocha palette. It intentionally omits C, Rust, Go, Node.js, Bun, PHP, Java, Kotlin, Haskell, and Python version segments. It retains OS, username, directory, Git state, Conda environment, time, and command duration.

## Ownership and rollback

Shell profiles use these exact markers:

```text
# >>> setup-starship-catppuccin >>>
# <<< setup-starship-catppuccin <<<
```

Installation refuses foreign Starship initialization instead of adding a second hook. Timestamped profile backups remain next to the original file.

The first unmanaged `starship.toml` is saved as `starship.toml.setup-starship-catppuccin.backup`. A SHA-256 sidecar records the installed asset. Removal restores the backup only when the current file still matches the recorded managed version. A user-edited managed config blocks removal until reviewed.

Font files follow the same rule: replace only after preserving a conflicting file, and remove only when the installed bytes still match the bundled asset. Removal retains the Starship executable/package because the package may have existed before this skill.

Windows Terminal settings are parsed as JSON. Installation records only the prior `profiles.defaults.font.face` state, writes `CaskaydiaCove NF`, and backs up the settings file. Removal restores that property without reverting unrelated settings changed later.

## Platform details

### Linux and WSL

The Bash installer uses Starship's official install script only when no executable is available. It installs to `~/.local/bin`, then places an owned PATH and initialization block in each selected shell profile. Linux font files go to `~/.local/share/fonts/CaskaydiaCoveNF`.

Linux font installation does not affect a Windows-hosted WSL terminal. Use `--with-windows` to invoke the Windows installer through the explicit mounted PowerShell path. This does not re-import Windows PATH into WSL.

### Windows

The Windows installer uses the `Starship.Starship` WinGet package with `--scope user`. It registers four CaskaydiaCove files under the current-user font registry using full absolute paths. Windows exposes the bundled family as `CaskaydiaCove NF`; using `CaskaydiaCove Nerd Font` in Terminal settings produces a missing-font warning.

Configure the Windows PowerShell 5.1 profile and the PowerShell 7 profile only when PowerShell 7 is installed or its profile directory exists. Keep existing functions, aliases, proxy configuration, and PSReadLine setup intact.

## Restart scope

- Shell profile or config only: start a new shell. Starship config changes appear on the next prompt when Starship is already active.
- WinGet user PATH: close all Windows Terminal windows and start Windows Terminal again.
- Windows user fonts or Terminal defaults: close all Windows Terminal windows and start it again. A new tab in an old Terminal process can inherit stale PATH and font enumeration.
- WSL PATH isolation changes are outside this skill. Do not run `wsl --shutdown` unless another workflow changed WSL host configuration.
