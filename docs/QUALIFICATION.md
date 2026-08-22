# Validation status — 0.6.65-r51

`0.6.65-r51` is the qualified engineering identity for the current `0.6.65` / build `51` macOS source. The application target remains Apple-silicon-only (`arm64`) with a macOS 26.0 deployment target, Swift 6 complete strict-concurrency checking, warnings-as-errors, and Hardened Runtime enabled.

## Exact-target qualification

The exact R51 candidate was validated on:

- macOS 26.6.2 (25G83);
- Xcode 26.6 (17F113);
- Swift 6.3.3;
- Apple silicon (`arm64`).

The exact-target validator completed clean Debug, clean Release, Release Analyze, SDK/API smokes, deterministic subtitle/database/playback-policy tests, generated local AVFoundation playback smoke, release-setting verification, documentation guards, and arm64 Mach-O inspection. The final validator result was:

`VALIDATION PASSED — EXACT TARGET XCODE DEBUG + RELEASE + ANALYZE + SDK SMOKES`

The validator is fail-closed for compiler diagnostics. The only allowed Xcode tool warning is the exact `appintentsmetadataprocessor` message `Metadata extraction skipped. No AppIntents.framework dependency found.`, and it is allowed only after the validator confirms that the application has no AppIntents/AppShortcuts dependency or registration path.

## Target-Mac runtime evidence

Manual target-Mac testing established:

- local MP3 playback reaches ready/playing state and advances the AVPlayer timebase;
- resume, pause/resume, exact seek, end-of-item, subtitle synchronization, and library/player handoff work;
- Prepare All cancellation and the R51 Dismiss regression close cleanly without leaving the stale empty popover;
- quitting while subtitle preparation is active did not expose a user-visible corruption or runaway condition;
- VoiceOver/accessibility navigation exercised for the release UI did not expose a blocking defect;
- Time Profiler showed no sustained Cuelixa CPU runaway and Thermal State remained Nominal;
- Allocations/Leaks testing showed no Cuelixa-owned leak in the captured run. Reported leak rows were in Apple LinkServices/Foundation/AppKit/XPC paths rather than Cuelixa frames.

Power Profiler is not available for macOS in the tested Instruments version, so no unsupported Power Profiler claim is made. Energy confidence is limited to the available Time Profiler/thermal/runtime evidence.

## Free-distribution integrity gate

The repository intentionally uses a no-paid-Apple-account distribution model. The release workflow therefore:

1. verifies `SOURCE-SHA256SUMS.txt` before building;
2. pins Xcode 26.6 / build 17F113 and verifies version/build/deployment metadata;
3. runs the CI validator gate;
4. produces an `arm64` Release app;
5. applies and verifies an ad-hoc code signature with Hardened Runtime options;
6. creates a read-only UDZO DMG containing `Cuelixa.app` and an `Applications` symlink;
7. verifies, mounts, and re-checks the frozen DMG;
8. generates and immediately verifies the final DMG SHA-256 file;
9. publishes only the DMG and matching checksum for a matching `v0.6.65` tag.

Ad-hoc signing is not Developer ID identity and is not notarization. The project makes no Apple notarization, government certification, ISO certification, or legal-compliance claim.

## Integrity files

`SOURCE-SHA256SUMS.txt` covers every tracked release-tree file except the manifest itself. The DMG release receives a separate `Cuelixa-0.6.65-macOS-arm64.dmg.sha256` after packaging is frozen.
