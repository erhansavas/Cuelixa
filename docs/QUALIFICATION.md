# Testing status — Cuelixa 0.7 (build 53)

Version 0.7 is the current source version; a matching release package has not been published. Current validation uses an Apple silicon Mac running macOS 27.0 (26A5425a), Xcode 27.0 (27A5252f), and Swift 6.4.

## Automated checks

The audit branch expands coverage to 37 Swift Testing unit/integration tests, two XCTest performance tests, and four native UI scenarios. The validator includes Debug and Release builds, Analyze, SDK/API smokes, local AVFoundation playback, source-manifest verification, strict concurrency, and warnings-as-errors.

The native UI scenarios verify isolated libraries, search, completion persistence, keyboard playback, close/reopen, scoped accessibility checks, and resizing in light and dark appearances. Exact run evidence and remaining accessibility limitations are recorded in [AUDIT-REPORT.md](../AUDIT-REPORT.md).

The scanner fixture verifies 1,000 unchanged files with zero hashes and one database transaction. Performance tests record CPU, memory, storage and wall-clock metrics. The subtitle timeline fixture covers 10,000 cues.

## Qualification boundary

Successful automated checks establish only the behaviors and environment exercised. They do not guarantee the absence of defects or establish complete VoiceOver, display/Spaces/fullscreen, accessibility-preference, or long-duration energy/leak qualification.

Further macOS 26 regression work was skipped at the user's request after two expanded UI scenarios failed there. The diagnostic run was canceled; those failures are not claimed resolved. Final audit qualification is macOS 27, while the minimum deployment target remains macOS 26.

Historical checks for the 0.6.66 baseline and earlier audit commits used macOS 26, Xcode 26.6 (17F113), and Swift 6.3.3. They do not qualify the current 0.7 source on macOS 26.

## Release package

The release workflow derives version/build identity from the Xcode project, verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks it, publishes its SHA-256 checksum, and creates GitHub build-provenance attestations.

Ad-hoc signing is not Developer ID signing or notarization.
