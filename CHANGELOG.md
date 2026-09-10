# Changelog

## Cuelixa 0.7.2 (build 55)

- Made Hide/Show Sidebar feel natural: opening or closing the sidebar no longer makes unrelated toolbar buttons jump.
- Clicking empty library content now releases Search focus without clearing the current query.
- Added UI regression tests for both fixes.

Cuelixa 0.7.2 is a focused UI-correctness patch over 0.7.1. Library data, transcription, playback, and persistence are otherwise unchanged.

## Cuelixa 0.7.1 (build 54)

- Keep scanner identity inside the canonical lesson-library hierarchy, handle safe internal symlinks deterministically, and reject external, dangling, or nonregular scanner targets.
- Revalidate recorded file identity before playback and subtitle preparation; transcription additionally verifies a stable snapshot against the lesson content hash before publishing a durable cache.
- Add regression coverage for symlink boundaries, canonical-target deduplication, external-symlink imports, and changed-source reconciliation.
- Add a maintained architecture document, consolidate release documentation, and separate historical audit evidence from current source-of-truth docs.
- Clarify source organization by giving the seek-slider source a truthful filename and keeping filesystem identity helpers with the local-file subsystem.
- Make release-note extraction deterministic and keep 0.7.1 pre-release status encoded in the release workflow while macOS 27 remains beta.
- Evaluate Swift CodeQL with GitHub's documented manual-build compatibility settings; omit the workflow after its traced build remained unreliable despite ordinary native validation being independent of CodeQL.

Permanent GitHub CI for 0.7.1 is configured to require a macOS 27 `xcode-27` host and run the complete validator. Hosted validation, repository presentation, and the independent exact-SHA macOS 27 run remain release gates until they have actually passed for the immutable final candidate.

## Cuelixa 0.7 (build 53)

- Require macOS 27 or later on Apple silicon; align the app, tests, validation, and release packaging with Xcode 27.
- Harden local audio, subtitle, transcript-cache, and database access against malformed input, unsafe paths, symlink substitution, and blocking special files.
- Protect import cleanup from concurrent imports and preserve discoverable filenames when importing audio through symlinks.
- Improve Unicode search and treat `%` and `_` as literal search text.
- Restore Space/Return playback after lesson selection and prevent playback updates during SwiftUI focus handling.
- Improve selection, lesson-duration, and playback-time contrast while retaining the coral identity.
- Add a native Icon Composer source and refresh the README with matching icons and macOS 27 screenshots.
- Expand coverage to 37 unit/integration tests, two performance tests, and four isolated native UI scenarios; validate Debug, Release, and Analyze with Xcode 27.
- Update the pinned release-attestation action to v4.2.2.

The full runtime and UI suite runs on macOS 27. Hosted CI compiles and analyzes with Xcode 27; remaining accessibility and extended-runtime qualification limits are recorded in [Testing](docs/QUALIFICATION.md).

## Cuelixa 0.6.66 (build 52)

- Validate the legacy library root before selecting it and isolate filesystem paths per process.
- Serialize imports, verify copied bytes, prevent destination races, and surface per-file failures.
- Reconcile scanner results with one prepared-statement SQLite transaction and skip hashing unchanged files.
- Add Swift Testing integration, isolated UI launch coverage, database/import/path tests, and performance metrics.
- Avoid redundant AppKit overlay assignments while preserving 10 Hz playback timing.
- Derive release identity from Xcode metadata and attest release artifacts through GitHub Actions.

Distribution is free and ad-hoc signed. The release is not Apple Developer ID signed or notarized.

## Cuelixa 0.6.65 (build 51)

- Native SwiftUI/AppKit macOS application for Apple silicon.
- Local audio library with search, resume, completion state, and filesystem observation.
- AVFoundation playback with confirmed-start handling, seeking, MediaPlayer integration, and global shortcuts.
- On-device subtitle preparation using Apple Speech APIs, local transcript caching, and synchronized subtitle display.
- Movable nonactivating subtitle/player panel designed to remain useful across normal app and Space/fullscreen workflows.
- SQLite-backed local state with WAL mode.
- Privacy manifest, local-first data model, hardened runtime build setting, strict Swift concurrency, and warnings-as-errors.
- Final cancellation/presentation-state fix prevents an empty subtitle-preparation popover from remaining after dismissal.

Source can be validated with `./VALIDATE-MAC.sh` on the exact qualification toolchain. The GitHub release is a free ad-hoc-signed DMG; because no paid Developer ID is used, macOS requires one manual **Open Anyway** approval after download.
