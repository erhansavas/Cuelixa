# Testing status — Cuelixa 0.6.66 (build 52)

The Cuelixa 0.6.66 release baseline was qualified on:

- macOS 26.6.2 (25G83)
- Xcode 26.6 (17F113)
- Swift 6.3.3
- Apple silicon (`arm64`)

## Automated checks

The audit branch expands coverage to 37 Swift Testing unit/integration tests, two XCTest performance tests, and four native UI scenarios. The validator includes Debug and Release builds, Analyze, SDK/API smokes, local AVFoundation playback, source-manifest verification, strict concurrency, and warnings-as-errors.

The current audit is validated with full Xcode 27.0 (27A5252f), Swift 6.4, and macOS 27.0 (26A5425a). The native UI scenarios verify isolated libraries, search, completion persistence, keyboard playback, close/reopen, scoped accessibility checks, and resizing in light and dark appearances. Exact run evidence and remaining accessibility limitations are recorded in [AUDIT-REPORT.md](../AUDIT-REPORT.md).

The scanner fixture verifies 1,000 unchanged files with zero hashes and one database transaction. Performance tests record CPU, memory, storage and wall-clock metrics. The subtitle timeline fixture covers 10,000 cues.

## Qualification boundary

Only results produced by the current validator and GitHub check are release claims. The project does not convert historical manual observations into current performance, accessibility or leak claims.

Further macOS 26 regression work was skipped at the user's request after two expanded UI scenarios failed there. The diagnostic run was canceled; those failures are not claimed resolved. Final audit qualification is macOS 27, while the minimum deployment target remains macOS 26.

## Release package

The release workflow derives version/build identity from the Xcode project, verifies source integrity, builds an `arm64` Release application, applies an ad-hoc signature with Hardened Runtime, creates a read-only DMG, mounts and rechecks it, publishes its SHA-256 checksum, and creates GitHub build-provenance attestations.

Ad-hoc signing is not Developer ID signing or notarization.
