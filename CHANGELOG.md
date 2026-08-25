# Changelog

All notable user-facing changes are recorded here. This project follows Semantic Versioning for versioned Git tags and GitHub Releases and never reuses a published version identifier.

## [0.2.0] - 2026-08-25

### Added

- Cross-terminal Nerd Font troubleshooting for Ghostty, Codex, Visual Studio Code, and Kiro, including font-family discovery, deterministic glyph checks, settings precedence, and restart boundaries.
- Version-pinned installation guidance and an explicit source-only GitHub delivery model for reproducible installs on other developer machines.

### Fixed

- Accepted normal Windows Terminal JSONC settings with comments and trailing commas while preserving string literals.
- Restored pre-existing conflicting Windows font files and their exact user registry values during removal.
- Verified the four bundled font files against `SHA256SUMS` at installer runtime before managed changes.
- Rejected production path overrides that could write outside current-user application and profile locations.
- Reported missing Windows Terminal settings as incomplete state and stopped installation during preflight instead of returning false readiness.

### Changed

- Clarified GNU/Linux and WSL as the automated Bash scope, with macOS retained as manual terminal-font diagnosis only.
- Documented preflight, component-level recovery, restart requirements, and the non-transactional WSL-to-Windows boundary.

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
