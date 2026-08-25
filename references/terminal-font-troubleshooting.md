# Terminal Font Troubleshooting

Use this guide when the Starship prompt renders correctly in one terminal host but Powerline separators, operating-system marks, or other Nerd Font symbols are missing or garbled in another. This is manual diagnostic guidance. The repository installers do not manage Ghostty, Codex, Visual Studio Code, Kiro, or macOS application settings.

## Separate the two rendering layers

Starship produces prompt text and escape sequences. The terminal host chooses the font that renders those characters. A working shell configuration therefore does not prove that every terminal application is using a Nerd Font, and an integrated terminal does not inherit another application's font setting.

| Symptom | Inspect first |
| --- | --- |
| The prompt is absent or falls back to a plain shell prompt | Interactive shell initialization, the active Starship config, and the terminal environment |
| Prompt colors and segments appear, but symbols are boxes, question marks, or blank cells | The failing terminal host's font family and glyph coverage |
| Only one terminal application is affected | That application's active font setting, then profile, remote, or workspace overrides where that host supports them |
| Every terminal is affected | Font installation, the exact family name exposed by the OS, and the configured fallback stack |

Do not reinstall Starship merely because one terminal host cannot render private-use glyphs.

## Audit before changing settings

Confirm that the affected terminal is running an interactive shell and that Starship is available. Use the example for that shell instead of copying syntax between shells.

Bash or Zsh:

```sh
command -v starship
printf 'STARSHIP_CONFIG=%s\n' "${STARSHIP_CONFIG:-$HOME/.config/starship.toml}"
```

Fish:

```fish
type -p starship
if set -q STARSHIP_CONFIG
    echo "STARSHIP_CONFIG=$STARSHIP_CONFIG"
else
    echo "STARSHIP_CONFIG=$HOME/.config/starship.toml"
end
```

Windows PowerShell 5.1 or PowerShell 7:

```powershell
Get-Command starship -ErrorAction Stop
$configPath = if ($env:STARSHIP_CONFIG) { $env:STARSHIP_CONFIG } else { Join-Path $HOME '.config\starship.toml' }
"STARSHIP_CONFIG=$configPath"
```

For Zsh, confirm that the interactive configuration initializes Starship and that no later profile fragment replaces `PROMPT` or `RPROMPT`. Test login and non-login interactive shells when the terminal hosts launch them differently. A non-interactive diagnostic subprocess may report `TERM=dumb`; do not treat that artifact as the affected terminal's runtime value.

Next, identify the exact family used by a known-good host. Ghostty can report valid family names:

```sh
ghostty +list-fonts
ghostty +show-config | grep '^font-family'
```

Where Fontconfig is available, `fc-match '<family>'` and `fc-scan <font-file>` can verify resolution and advertised aliases. On macOS without Fontconfig, use Font Book or the application's own font picker. Match the family name, not the font filename.

Run the corresponding deterministic glyph sample in every terminal host.

Bash or Zsh:

```sh
printf '%s\n' '     '
```

Fish:

```fish
printf '%s\n' '     '
```

Windows PowerShell 5.1 or PowerShell 7:

```powershell
[Console]::WriteLine("$([char]0xE0B6) $([char]0xE0B0) $([char]0xE0B4) $([char]0xF418) $([char]0xF43A) $([char]0xEAF4)")
```

Each example emits the same six code points from the preset: left and right Powerline separators, Git branch mark, time mark, and command-duration mark. All six glyphs should be visible, and the separators should occupy a normal terminal cell without replacement boxes.

## Use one installed Nerd Font across hosts

The macOS repair that motivated this guide used the installed family `FiraCode Nerd Font Mono`; it covered every glyph in the sample. That is an example, not a repository dependency.

This repository bundles CaskaydiaCove Nerd Font and its installers own only that bundled state. Windows exposes the installed family as `CaskaydiaCove NF`; other systems may advertise `CaskaydiaCove Nerd Font` as an alias. Discover the name exposed on the target system instead of copying a family string from another OS or substituting FiraCode for the bundled asset.

### Ghostty

Set `font-family` to the exact name returned by `ghostty +list-fonts`:

```text
font-family = FiraCode Nerd Font Mono
```

Reload the configuration and open a new terminal surface before validating. A correct Ghostty setting affects Ghostty only.

### Codex desktop app

The official OpenAI documentation confirms that Codex exposes a **Code font** control under **Settings → Appearance**, but it does not document how the integrated terminal selects its font. Inspect the controls exposed by the current build first.

In the macOS repair that motivated this guide, the following value worked in the Code font control:

```text
"FiraCode Nerd Font Mono", ui-monospace, monospace
```

That result was verified empirically against Codex build `26.818.41509`: local bundle inspection and live behavior showed the integrated terminal consuming the active code-font value, and no separate terminal font-family control was observed. Neither the input syntax nor the terminal inheritance is a documented public contract. Re-check the official OpenAI documentation and the current UI after upgrades. If the Code font control does not affect the terminal, stop instead of editing Codex's internal persisted state.

The Code font setting also affects other code surfaces and is user-level, so explain its cross-project impact before changing it.

Close and reopen the terminal panel. Restart the app only if the existing process retains stale font state.

### Visual Studio Code and Kiro

Kiro preserves standard VS Code settings, including the integrated terminal font family. In each application's **User** settings, configure:

```jsonc
{
  "terminal.integrated.fontFamily": "'FiraCode Nerd Font Mono', monospace"
}
```

Prefer the Settings UI or a minimal edit that preserves unrelated keys. VS Code settings files are JSON with Comments (JSONC) and may contain comments or trailing commas; strict JSON tools such as `jq` can reject a valid VS Code settings file. Use the editor's diagnostics or a JSONC-aware parser instead.

The active profile selects which user-settings file applies. After that selection, remote, workspace, and workspace-folder settings can override the active user setting. Inspect the active profile and every later scope before concluding that the user setting was ignored. Kiro follows the same VS Code settings architecture for standard preferences.

Create a new integrated terminal after changing the setting. If the old renderer remains active, run **Developer: Reload Window**. Restarting the entire application is the final fallback, not the first step.

## Permission and restart boundaries

- Explain and obtain approval before changing a user-level application setting because it affects unrelated projects and workspaces.
- Keep app-font repair separate from the repository installers and their rollback state.
- A Starship config change appears on the next prompt when Starship is already active.
- A shell initialization change requires a new interactive shell.
- A terminal font change may require a new terminal surface, a window reload, or an app restart, depending on the host.
- Do not claim success until the glyph sample and a real Starship prompt render correctly in every requested host.

## Supported boundary

This manual workflow helps diagnose macOS and integrated-terminal rendering, but it does not make macOS release-qualified. The automated compatibility statement remains limited to the platforms and terminal state documented in [platform behavior](platform-behavior.md). Consult [official sources](sources.md) before relying on version-sensitive application behavior.
