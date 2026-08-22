# Changelog

This project records user-visible releases here. Internal engineering revision numbers are intentionally not presented as separate product versions.

## 0.6.65 — 2026-08-22

### macOS native release baseline

- Native SwiftUI/AppKit macOS application for Apple silicon.
- Local audio library with search, resume, completion state, and filesystem observation.
- AVFoundation playback with confirmed-start handling, seeking, MediaPlayer integration, and global shortcuts.
- On-device subtitle preparation using Apple Speech APIs, local transcript caching, and synchronized subtitle display.
- Movable nonactivating subtitle/player panel designed to remain useful across normal app and Space/fullscreen workflows.
- SQLite-backed local state with WAL mode.
- Privacy manifest, local-first data model, hardened runtime build setting, strict Swift concurrency, and warnings-as-errors.
- Final cancellation/presentation-state fix prevents an empty subtitle-preparation popover from remaining after dismissal.

### Distribution

- Source can be validated with `./VALIDATE-MAC.sh` on the exact qualification toolchain.
- GitHub release packaging supports a free ad-hoc-signed DMG. Because no paid Developer ID is used, macOS requires one manual **Open Anyway** approval after download.
