# Publication policy

## Scope

This repository publishes the Cuelixa source code and a free macOS Apple-silicon DMG through GitHub Releases.

## Public artifacts

- `Cuelixa-0.6.65-macOS-arm64.dmg`
- `Cuelixa-0.6.65-macOS-arm64.dmg.sha256`

## Publication gates

- supported local build and test sequence passes;
- GitHub CI passes;
- complete tracked-path and source-digest verification passes;
- manual runtime and accessibility checks pass;
- performance, thermal, and memory inspection shows no application-owned runaway or leak;
- release bundle is `arm64` and its version/build metadata match;
- ad-hoc code signature verifies with Hardened Runtime;
- read-only DMG verifies and remounts successfully;
- final DMG SHA-256 is generated and verified after packaging;
- license, notices, privacy/security documentation, and release notes match the published source revision.

## Free-distribution security posture

The release must never ask users to disable Gatekeeper or SIP or clear quarantine through Terminal. If macOS blocks first launch because the build is not Developer ID notarized, documentation must use the standard **Privacy & Security → Open Anyway** approval flow.

An ad-hoc signature is not developer authentication or notarization; it provides only a consistent code-signing seal for the packaged application.
