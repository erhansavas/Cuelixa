# Publication policy

## Scope

This repository publishes the Cuelixa source code and a free macOS Apple-silicon DMG through GitHub Releases.

Release identity: **Cuelixa 0.7 (build 53)** under tag **`v0.7`**, requiring macOS 27 or later on Apple silicon.

## Public artifacts

- `Cuelixa-0.7-macOS-arm64.dmg`
- `Cuelixa-0.7-macOS-arm64.dmg.sha256`

## Publication gates

- the full local macOS 27 build and runtime/UI test sequence passes;
- GitHub Xcode 27 build-only CI passes, with its host/runtime limitation documented;
- complete tracked-path and source-digest verification passes;
- unit, integration, UI-launch and performance tests pass;
- release bundle is `arm64`, minimum macOS is `27.0`, and version/build metadata match;
- ad-hoc code signature verifies with Hardened Runtime;
- read-only DMG verifies and remounts successfully;
- final DMG SHA-256 is generated and verified after packaging;
- GitHub build-provenance attestations cover the frozen DMG and checksum;
- license, notices, privacy/security documentation, and release notes match the published source revision;
- `v0.7`, the application metadata, DMG name and checksum filename agree exactly.

## Free-distribution security posture

The release must never ask users to disable Gatekeeper or SIP or clear quarantine through Terminal. If macOS blocks first launch because the build is not Developer ID notarized, documentation must use the standard **Privacy & Security → Open Anyway** approval flow.

An ad-hoc signature is not developer authentication or notarization; it provides only a consistent code-signing seal for the packaged application.
