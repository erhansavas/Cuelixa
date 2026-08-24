# Testing status — Cuelixa 0.6.66 (build 52)

The exact Cuelixa 0.6.66 source tree is qualified on:

- macOS 26.6.2 (25G83)
- Xcode 26.6 (17F113)
- Swift 6.3.3
- Apple silicon (`arm64`)

## Automated checks

The supported validator and required `macos-arm64-release` GitHub check pass for the release tree. Coverage includes 19 Swift Testing unit/integration tests, two XCTest performance tests, the isolated-root UI launch test, Debug and Release builds, Analyze, SDK/API smokes, local AVFoundation playback, source-manifest verification, strict concurrency, and warnings-as-errors.

The scanner fixture verifies 1,000 unchanged files with zero hashes and one database transaction. Performance tests record CPU, memory, storage and wall-clock metrics. The subtitle timeline fixture covers 10,000 cues.

## Qualification boundary

Only results produced by the current validator and GitHub check are release claims. The project does not convert historical manual observations into current performance, accessibility or leak claims.

## Release package

The release workflow derives version/build identity from the Xcode project, verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks it, publishes its SHA-256 checksum, and creates GitHub build-provenance attestations.

Ad-hoc signing is not Developer ID signing or notarization.
