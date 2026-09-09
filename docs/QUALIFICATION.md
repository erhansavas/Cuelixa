# Qualification — Cuelixa 0.7.1 (build 54)

Cuelixa 0.7.1 requires an Apple silicon Mac running macOS 27.0 or later. The release qualification target is macOS 27 beta 8 (`26A5425a`), Xcode 27 beta 6 (`27A5252f`), and Swift 6.4.

This document defines what must be proven. It intentionally does not embed a mutable “latest successful run” claim that would require changing the source tree after the exact candidate SHA has been qualified. The PR/Actions/release evidence records the actual run result for that immutable candidate.

## Complete validator

`VALIDATE-MAC.sh` is the authoritative local qualification entry point. In normal mode on macOS 27 it covers:

- source-manifest verification and tracked-source/project membership;
- Swift parsing/formatting and project/resource integrity;
- strict concurrency and warnings-as-errors through project builds;
- deterministic utility, database, import/scanner, subtitle, cancellation, source-identity, and local AVFoundation smoke checks;
- the Swift Testing unit/integration suite;
- XCTest performance coverage;
- native UI scenarios using an isolated test library;
- clean Debug and Release builds;
- Xcode Analyze;
- deployment target, `arm64` architecture, bundle identifier, version/build, and Release-bundle checks;
- the same release-note extraction script used by the permanent release workflow.

The final 0.7.1 candidate must pass the **complete** validator on an actual supported macOS 27 runtime. The complete output is release evidence and must correspond to the exact candidate SHA.

## Regression focus

The 0.7.1 suite includes regression coverage for the source-identity work added after 0.7, including regular in-library audio, safe internal symlinks, rejection of external/dangling/special scanner targets, deterministic canonical-target deduplication, import-through-external-symlink copying, and changed-source rehash/reconciliation behavior.

The scanner performance fixture retains the legacy per-record database path as a test comparison so the one-transaction reconciliation path can be measured against its predecessor. That test capability is not evidence that the legacy path is used by the application scanner.

## Hosted CI boundary

GitHub's `xcode-27` Apple silicon image supplies the Xcode 27 beta 6 toolchain but currently runs a macOS 26 host. The permanent `macos-arm64-release` job therefore runs the validator with `CUELIXA_BUILD_ONLY=1`.

That mode compiles the macOS 27 application/test/smoke targets, builds Debug and Release, runs Analyze, and verifies source/bundle metadata, but it deliberately **does not execute** binaries that require the macOS 27 runtime. Hosted success is build/compile/Analyze evidence only.

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

Earlier engineering qualification and macOS 26/0.6.66 evidence is preserved under [Historical audits](audits/). It is not current architecture or proof of the 0.7.1 candidate.

## Release package

After the exact candidate passes local macOS 27 qualification and repository gates, the tagged release workflow independently verifies package identity, produces an `arm64` read-only DMG, verifies the ad-hoc Hardened Runtime signature, freezes/verifies SHA-256, and requests GitHub artifact attestations. See [RELEASE.md](RELEASE.md).

Ad-hoc signing is not Developer ID signing or notarization.
