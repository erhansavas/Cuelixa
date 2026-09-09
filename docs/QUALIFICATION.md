# Qualification — Cuelixa 0.7.1 (build 54)

Cuelixa 0.7.1 requires an Apple silicon Mac running macOS 27.0 or later. The release qualification target is macOS 27 beta 8 (`26A5425a`), Xcode 27 beta 6 (`27A5252f`), and Swift 6.4.

This document defines what must be proven. It intentionally does not embed a mutable “latest successful run” claim that would require changing the source tree after the exact candidate SHA has been qualified. The PR/Actions/release evidence records the actual run result for that immutable candidate.

## Complete validator

`VALIDATE-MAC.sh` is the authoritative qualification entry point. In normal mode on macOS 27 it covers:

- source-manifest verification and tracked-source/project membership;
- Swift parsing/formatting and project/resource integrity;
- strict concurrency and warnings-as-errors through project builds;
- deterministic utility, database, import/scanner, subtitle, cancellation, source-identity, and local AVFoundation smoke checks;
- the Swift Testing unit/integration suite;
- XCTest performance coverage;
- native UI scenarios using an isolated test library;
- clean Debug and Release builds;
- Xcode Analyze;
- deployment target, `arm64` architecture, bundle identifier, version/build, and Release-bundle checks.

The final 0.7.1 candidate must pass the **complete** validator on an actual supported macOS 27 runtime. The complete output is release evidence and must correspond to the exact candidate SHA.

## Regression focus

The 0.7.1 suite includes regression coverage for the source-identity work added after 0.7, including regular in-library audio, safe internal symlinks, rejection of external/dangling/special scanner targets, deterministic canonical-target deduplication, import-through-external-symlink copying, and changed-source rehash/reconciliation behavior.

The scanner performance fixture retains the legacy per-record database path as a test comparison so the one-transaction reconciliation path can be measured against its predecessor. That test capability is not evidence that the legacy path is used by the application scanner.

## Hosted CI boundary

The permanent `macos-arm64-release` job uses GitHub's Apple silicon `xcode-27` image and explicitly requires the host to report macOS major version 27 before running the complete validator. It also records `sw_vers`, Xcode, and Swift versions in the Actions log. The final candidate run, not an assumption in this document, proves the hosted runtime actually used for qualification.

Hosted qualification and the independent exact-SHA run on the user's own supported Mac are separate release gates. Hosted success does not replace the user-machine gate.

## What qualification does not claim

Passing the automated gates establishes only the exercised behaviors and environment. It does not establish exhaustive coverage of:

- VoiceOver and Full Keyboard Access combinations;
- Reduce Motion, Reduce Transparency, or Increase Contrast combinations;
- every multiple-display, Spaces, or fullscreen arrangement;
- very long playback/idle sessions;
- exhaustive energy/leak characterization;
- behavior in the presence of a malicious process already running as the same macOS user.

These are truthful qualification boundaries, not known defects unless a failing behavior is actually observed.

## Historical evidence

Earlier engineering evidence is preserved under [Historical audits](audits/). It is not current architecture or proof of the 0.7.1 candidate.

## Release package

After the exact candidate passes hosted and independent macOS 27 qualification plus repository/presentation gates, the tagged release workflow independently verifies package identity, produces an `arm64` read-only DMG, verifies the ad-hoc Hardened Runtime signature, freezes/verifies SHA-256, and requests GitHub artifact attestations. See [RELEASE.md](RELEASE.md).

Ad-hoc signing is not Developer ID signing or notarization.
