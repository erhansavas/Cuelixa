# Testing status — 0.6.65

Cuelixa 0.6.65 was tested on:

- macOS 26.6.2 (25G83)
- Xcode 26.6 (17F113)
- Swift 6.3.3
- Apple silicon (`arm64`)

## Automated checks

The local validator completed clean Debug and Release builds, Release Analyze, SDK/API smoke tests, deterministic subtitle/database/playback-policy tests, generated local AVFoundation playback testing, release-setting verification, and `arm64` Mach-O inspection. Compiler warnings are treated as errors and Swift complete strict-concurrency checking remains enabled.

GitHub Actions repeats the source-integrity, build, analysis, and smoke-test gates on an Apple-silicon macOS runner.

## Runtime testing

Manual testing covered:

- local audio playback, pause/resume, exact seek, end-of-item handling, and library/player handoff;
- resume and completion state;
- synchronized subtitles and immediate playback of newly prepared subtitles;
- subtitle preparation, cancellation, batch processing, and safe quit;
- VoiceOver and keyboard navigation of the release interface;
- Time Profiler, thermal-state, Allocations, and Leaks inspection.

The captured runs showed no sustained Cuelixa CPU runaway or Cuelixa-owned memory leak. Power Profiler was not available for macOS in the tested Instruments release, so no unsupported Power Profiler claim is made.

## Release package

The release workflow verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks the packaged application, and publishes the DMG with its verified SHA-256 checksum.

Ad-hoc signing is not Developer ID signing or notarization.
