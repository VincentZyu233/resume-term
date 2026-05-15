# Build Workflow

This repository uses commit messages to control CI.

## Trigger keywords
- `build action`: run analysis and desktop builds
- `build release`: run analysis, desktop builds, and create a GitHub Release

## Target platforms
- Windows x64
- Linux x64

## Notes
- The workflow bootstraps Flutter desktop platform folders with `flutter create`
- Local Flutter is not required for day-to-day iteration if CI is the validation path

