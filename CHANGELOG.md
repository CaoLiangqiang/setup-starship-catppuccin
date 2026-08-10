# Changelog

All notable user-facing changes are recorded here. This project follows Semantic Versioning for immutable Git tags and GitHub Releases.

## [0.1.0] - 2026-08-10

### Added

- User-scoped Starship installation and Catppuccin Mocha Powerline configuration for Linux and WSL.
- Explicit Windows-host setup for WinGet Starship, PowerShell profiles, user fonts, and Windows Terminal.
- Four bundled CaskaydiaCove Nerd Font faces with SIL OFL 1.1 licensing and SHA-256 checksums.
- Bash, Zsh, and Fish discovery with configurable shell scope.
- Managed markers, backups, content hashes, collision checks, idempotent installation, and targeted rollback.
- Linux and Windows fixture tests plus GitHub Actions validation.
- Repository-native Agent Skill metadata, workflow guidance, platform documentation, and release README.

### Safety

- Kept Linux, WSL, and Windows changes user-scoped without sudo, UAC, or machine-wide PATH edits.
- Made all Windows changes explicitly opt-in through `--with-windows` or the dedicated PowerShell installer.
- Preserved user-edited managed state by refusing unsafe replacement or removal.
