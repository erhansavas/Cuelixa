# Testing status — Cuelixa 0.7 (build 53)

Cuelixa 0.7 requires macOS 27 or later and Apple silicon. Current validation uses an Apple silicon Mac running macOS 27.0 (26A5425a), Xcode 27.0 (27A5252f), and Swift 6.4.

## Automated checks

The automated suite contains 37 Swift Testing unit/integration tests, two XCTest performance tests, and four native UI scenarios. All 43 passed with the macOS 27 minimum target on 2026-09-08. The validator also passed Debug and Release builds, Analyze, SDK/API smokes, local AVFoundation playback, strict concurrency, and warnings-as-errors. Source-manifest verification passed separately.

The native UI scenarios verify isolated libraries, search, completion persistence, keyboard playback, close/reopen, scoped accessibility checks, and resizing in light and dark appearances. Exact run evidence and remaining accessibility limitations are recorded in [AUDIT-REPORT.md](../AUDIT-REPORT.md).

The scanner fixture verifies 1,000 unchanged files with zero hashes and one database transaction. Performance tests record CPU, memory, storage and wall-clock metrics. The subtitle timeline fixture covers 10,000 cues.

## Qualification boundary

Successful automated checks establish only the behaviors and environment exercised. They do not guarantee the absence of defects or establish complete VoiceOver, display/Spaces/fullscreen, accessibility-preference, or long-duration energy/leak qualification.

The minimum deployment target is macOS 27.0 for the app and both test targets. Earlier macOS 26 UI failures remain historical audit evidence; macOS 26 is outside the supported range for version 0.7.

Historical checks for the 0.6.66 baseline and earlier audit commits used macOS 26, Xcode 26.6 (17F113), and Swift 6.3.3. They do not establish current release qualification.

## Hosted CI

The `xcode-27` runner provides the same Xcode 27 beta 6 toolchain but currently runs macOS 26. Hosted checks compile all macOS 27 test targets and smoke executables, clean-build Debug and Release, run Analyze, and verify source and bundle integrity. `CUELIXA_BUILD_ONLY=1` reports runtime tests as unexecuted; the full local macOS 27 run supplies that separate evidence.

## Release package

The release workflow derives version/build identity from the Xcode project, verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks it, publishes its SHA-256 checksum, and creates GitHub build-provenance attestations.

Local execution of the workflow's packaging steps passed image, metadata, signature, and checksum checks. The signed app inside the mounted read-only DMG launched and exited cleanly on macOS 27.

Ad-hoc signing is not Developer ID signing or notarization.
