# Testing status — 0.6.66 development

The unchanged R51 product baseline was previously tested on:

- macOS 26.6.2 (25G83)
- Xcode 26.6 (17F113)
- Swift 6.3.3
- Apple silicon (`arm64`)

## Automated checks

The 0.6.66 validator adds Swift Testing integration, a minimal isolated-root UI launch test, safe-import/path tests, batched SQLite reconciliation tests, and subtitle-timeline CPU, memory, storage, and wall-clock metrics to the existing Debug, Release, Analyze, SDK and AVFoundation gates. Compiler warnings remain errors and Swift complete strict-concurrency checking remains enabled.

Results for 0.6.66 are established only by a successful validator/CI run for the exact source revision. Historical R51 results are not automatically carried forward.

## Runtime testing

Historical R51 manual testing covered:

- local audio playback, pause/resume, exact seek, end-of-item handling, and library/player handoff;
- resume and completion state;
- synchronized subtitles and immediate playback of newly prepared subtitles;
- subtitle preparation, cancellation, batch processing, and safe quit;
- VoiceOver and keyboard navigation of the release interface;
- Time Profiler, thermal-state, Allocations, and Leaks inspection.

Those captured R51 runs showed no sustained Cuelixa CPU runaway or Cuelixa-owned memory leak. Manual runtime, accessibility and Instruments checks must be repeated before publishing 0.6.66. Power Profiler was not available for macOS in the tested Instruments release, so no unsupported Power Profiler claim is made.

## Release package

The release workflow derives version/build identity from the Xcode project, verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks it, publishes its SHA-256 checksum, and creates GitHub build-provenance attestations.

Ad-hoc signing is not Developer ID signing or notarization.
