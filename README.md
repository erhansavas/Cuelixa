<div align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cuelixa-icon-dark.png">
    <img src="docs/assets/cuelixa-icon.png" width="148" height="148" alt="Cuelixa app icon">
  </picture>
  <h1>Cuelixa</h1>
  <p><strong>Local-first listening practice for Apple silicon Macs.</strong></p>
  <p>Organize local lesson audio, resume where you left off, prepare subtitles on-device, and keep synchronized text in a compact floating player.</p>
  <p><strong>Cuelixa 0.7.1 · Build 54</strong></p>

  [![macOS CI](https://github.com/erhansavas/Cuelixa/actions/workflows/macos.yml/badge.svg)](https://github.com/erhansavas/Cuelixa/actions/workflows/macos.yml)
  [![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
</div>

> **Platform status:** Cuelixa 0.7.1 targets macOS 27.0 or later. macOS 27 remains beta during this release cycle, so the permanent 0.7.1 release workflow is configured to create a GitHub **Pre-release** when a validated tag is eventually published.

## What Cuelixa does

Cuelixa is a native macOS application for focused listening practice. It keeps the lesson library and listening state local, uses Apple Speech for on-device English transcription, and presents subtitles alongside AVFoundation playback without requiring an account or cloud backend.

- Browse/search local lessons and track completion or resume position.
- Use an existing same-basename SRT sidecar or prepare synchronized subtitles on-device.
- Queue subtitle preparation while keeping one Speech transcription job active at a time.
- Control playback from the floating subtitle overlay, keyboard shortcuts, or macOS Now Playing controls.
- Import supported audio by drag-and-drop while preserving the original source file.

## Screenshots

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/cuelixa-library.png">
    <img src="docs/screenshots/cuelixa-library-light.png" alt="Cuelixa lesson library with completion tracking and prepared subtitles" width="100%">
  </picture>
  <br>
  <sub>Native library navigation with completion and subtitle status</sub>
</p>

<p align="center">
  <img src="docs/screenshots/cuelixa-subtitle-options.png" alt="Cuelixa subtitle preparation options" width="100%">
  <br>
  <sub>Prepare subtitles locally or listen without them</sub>
</p>

<p align="center">
  <img src="docs/screenshots/cuelixa-playback-overlay.png" alt="Cuelixa subtitle-first playback overlay" width="100%">
  <br>
  <sub>Movable subtitle/transport overlay during active playback</sub>
</p>

## Engineering highlights

- Native Swift, SwiftUI and AppKit; no third-party package dependencies.
- AVFoundation playback state machine with async asset validation, seek/start watchdogs, stale-callback generation checks, and verified first-timebase progression before playback presentation.
- Apple Speech transcription through an actor-owned executor with explicit cancellation and a verified staging snapshot before durable transcript publication.
- SQLite persistence with serialized connection ownership, WAL mode, busy timeout, foreign keys, and transactional library reconciliation.
- Defensive local-file handling: canonical scanner containment, intentional symlink boundaries, regular-file checks, bounded reads, import byte verification, and atomic managed transcript publication.
- Content-addressed transcript cache that binds verified SRT bytes to the lesson audio SHA-256.
- Strict Swift concurrency and warnings-as-errors in the application target, plus unit/integration, performance, native UI, smoke, build, Analyze, and source-manifest gates.
- GitHub Actions use immutable action SHAs and least-privilege workflow permissions for their purpose.

See [Architecture](docs/ARCHITECTURE.md) for subsystem ownership, data flows, concurrency, invariants, and the security boundary.

## Requirements

- Apple silicon Mac (`arm64`)
- macOS 27.0 or later
- Full Xcode 27 to build from source

The 0.7.1 qualification target is macOS 27 beta 8 (`26A5425a`) with Xcode 27 beta 6 (`27A5252f`) and Swift 6.4. Permanent GitHub CI requires its `xcode-27` host to report macOS 27 before running the complete validator; the exact host version is recorded by the final candidate Actions run. Independent exact-SHA qualification on the user's own supported Mac remains a separate release gate.

## Install

Release artifacts are published on [GitHub Releases](https://github.com/erhansavas/Cuelixa/releases). When 0.7.1 passes every release gate, its intended artifacts are `Cuelixa-0.7.1-macOS-arm64.dmg` and `Cuelixa-0.7.1-macOS-arm64.dmg.sha256`.

1. Open the DMG.
2. Drag **Cuelixa** to **Applications**.
3. Open Cuelixa from Applications.

### First launch

The free GitHub build is ad-hoc signed with Hardened Runtime and is not claimed to be Developer ID signed or notarized. If macOS blocks the first launch, try opening Cuelixa once, then use **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. No Terminal command, SIP change, Gatekeeper disablement, or Recovery-mode change is required.

## Library and local data

New installations use `~/Music/Cuelixa`. A valid existing `~/podcast` library remains supported without destructive migration.

Supported source extensions are `mp3`, `m4a`, `aac`, `flac`, `wav`, `ogg`, and `opus`; actual decoding depends on AVFoundation support in the installed macOS release.

Application-owned data is stored under:

- `~/Library/Application Support/Cuelixa/`
- `~/Library/Application Support/Cuelixa/Transcripts/`
- `~/Library/Caches/Cuelixa/`

Same-basename `.srt` sidecars remain user-owned and usable in place. Cuelixa does not rename source audio.

## Build and test

Open `CuelixaMac.xcodeproj` in full Xcode, select **Cuelixa → My Mac**, and build. The complete qualification command is:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
./VALIDATE-MAC.sh
```

The validator checks source integrity/formatting, application and test compilation, Debug and Release builds, static analysis, deterministic smoke coverage, runtime/integration/performance tests, native UI scenarios, playback behavior, architecture guards, and final bundle metadata. Permanent pull-request CI runs this complete validator only after proving the hosted machine is an arm64 macOS 27 host with the required Xcode build.

See [Build](docs/BUILD.md) and [Qualification](docs/QUALIFICATION.md).

## Privacy and security posture

Cuelixa has no application-managed backend, account, advertising, analytics, or telemetry SDK. Audio, listening progress, and managed subtitles remain on the Mac; Apple Speech may ask macOS to install Apple-managed on-device speech assets.

Cuelixa is an **unsandboxed local application** and does not claim isolation from a malicious process already running as the same macOS user. Its filesystem hardening is defensive correctness around local files and app-owned state, not a claim that Cuelixa is a security product.

See [Privacy](docs/PRIVACY.md), [Security](SECURITY.md), [Architecture](docs/ARCHITECTURE.md), and the [sandbox decision](docs/SANDBOX-DECISION.md).

## Release integrity

The permanent release workflow derives version/build identity from Xcode, verifies the complete source manifest, compiles/analyzes the macOS 27 target, builds an `arm64` app with Hardened Runtime, applies an ad-hoc signature, creates and remounts a read-only DMG, freezes and verifies SHA-256, requests GitHub artifact attestations, and extracts only the matching changelog section for release notes. While macOS 27 remains beta, it deterministically marks the GitHub release as a Pre-release. Hosted and independent exact-SHA runtime qualification must already have passed before merge/tag.

`SOURCE-SHA256SUMS.txt` detects accidental release-tree drift; because it is stored in the same repository, it is not an independent trust root.

See [Release procedure](docs/RELEASE.md).

## Documentation

- [Architecture](docs/ARCHITECTURE.md) — subsystem ownership, flows, concurrency, invariants, security boundary
- [Build](docs/BUILD.md) — toolchain and validation commands
- [Qualification](docs/QUALIFICATION.md) — what the automated and manual gates establish
- [Release](docs/RELEASE.md) — release preparation, packaging and publication
- [Privacy](docs/PRIVACY.md) and [Security](SECURITY.md) — data handling and vulnerability scope
- [Historical audits](docs/audits/) — preserved engineering evidence, not current architecture

## License

Cuelixa first-party source is licensed under the Apache License 2.0. See [LICENSE](LICENSE), [NOTICE](NOTICE), and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
