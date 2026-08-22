# Publication policy

## Scope

This repository publishes source code and may publish a free macOS Apple-silicon DMG through GitHub Releases. No paid Apple Developer Program membership is required by the project release process.

## Public artifact names

- `Cuelixa-0.6.65-macOS-arm64.dmg`
- `Cuelixa-0.6.65-macOS-arm64.dmg.sha256`

The internal engineering identifier remains `0.6.65-r51` / build `51`, but engineering labels are not exposed in public artifact names.

## Mandatory publication gates

- exact-target `VALIDATE-MAC.sh` pass;
- complete tracked-path and digest verification through `Scripts/verify-source-manifest.sh`;
- manual runtime regression pass;
- accessibility pass;
- Time Profiler / thermal evidence without a Cuelixa runaway pattern;
- Allocations/Leaks evidence without a Cuelixa-owned leak;
- release bundle is `arm64` and version/build metadata match;
- ad-hoc code signature verifies;
- read-only DMG verifies and remounts successfully;
- final DMG SHA-256 is generated and verified after packaging;
- `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, privacy/security documentation, and release notes match the published source revision.

## Security posture for free distribution

The release must never tell users to disable Gatekeeper, disable SIP, or clear quarantine with Terminal commands. If macOS blocks first launch because the build is not Developer-ID notarized, document only Apple's normal **Privacy & Security → Open Anyway** approval flow.

Do not describe an ad-hoc signature as developer authentication, notarization, or Apple trust. It only gives the bundle a consistent code-signing seal.
