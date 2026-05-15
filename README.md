# Resume-Term

Cross-platform workspace manager for terminal layouts and restorable terminal workspaces.

Each pane can restore a shell by itself, such as `PowerShell`, `cmd`, or `/bin/bash`, and can optionally start with a command. Common examples include `ssh`, `htop`, `btop`, `nload`, `tail -f`, or any other command you want to keep in a saved layout.

## Scope
- Windows x64
- Linux x64

## CI trigger
- Commit message contains `build action` for build
- Commit message contains `build release` for build + release

## Layout
- `lib/` Flutter UI
- `rust/` Rust core
- `docs/` planning and examples
